///|
suberror TransportFailure {
  TransportFailure(String)
} derive(Debug)

///|
fn[T] transport_fail(message : String) -> T raise {
  raise TransportFailure(message)
}

///|
struct RawSession {
  reader : @process.ReadFromProcess
  writer : @process.WriteToProcess
  process : @process.Process
  mut finished : Bool
  mut carry : Array[Byte]
}

///|
struct StderrState {
  bytes : Array[Byte]
  mut overflow : Bool
}

///|
async fn drain_stderr(
  reader : @process.ReadFromProcess,
  state : Ref[StderrState],
  process : @process.Process,
) -> Unit {
  while !state.val.overflow {
    match reader.read_some(max_len=4096) {
      None => break
      Some(chunk) => {
        let room = 65536 - state.val.bytes.length()
        let count = if chunk.length() < room { chunk.length() } else { room }
        for i = 0; i < count; i = i + 1 {
          state.val.bytes.push(chunk[i])
        }
        if count < chunk.length() {
          state.val.overflow = true
          process.cancel()
          transport_fail("stderr exceeds 65536 bytes")
        }
      }
    }
  }
}

///|
async fn RawSession::read_response_line(self : RawSession) -> Json {
  while true {
    let mut newline : Int? = None
    for i = 0; i < self.carry.length(); i = i + 1 {
      if self.carry[i] == b'\n' {
        newline = Some(i)
        break
      }
    }
    match newline {
      Some(index) => {
        let bytes : Array[Byte] = []
        for i = 0; i < index; i = i + 1 {
          bytes.push(self.carry[i])
        }
        let rest : Array[Byte] = []
        for i = index + 1; i < self.carry.length(); i = i + 1 {
          rest.push(self.carry[i])
        }
        self.carry = rest
        let text = @utf8.decode(Bytes::from_array(bytes)) catch {
          _ => transport_fail("invalid UTF-8 response")
        }
        return @json.parse(text) catch {
          _ => transport_fail("invalid JSON response")
        }
      }
      None => ()
    }
    match self.reader.read_some(max_len=4096) {
      None => transport_fail("control process closed stdout")
      Some(chunk) => {
        for byte in chunk.iter() {
          self.carry.push(byte)
        }
        let mut newline : Int? = None
        for i = 0; i < self.carry.length(); i = i + 1 {
          if self.carry[i] == b'\n' {
            newline = Some(i)
            break
          }
        }
        match newline {
          Some(index) =>
            if index > 65536 {
              transport_fail("response line exceeds 65536 bytes")
            }
          None =>
            if self.carry.length() > 65536 {
              transport_fail("response line exceeds 65536 bytes")
            }
        }
      }
    }
  } nobreak {
    transport_fail("control response unavailable")
  }
}

///|
pub async fn RawSession::request(self : RawSession, raw : String) -> Json {
  @async.with_timeout(15000, () => {
    self.writer.write(raw + "\n")
    self.read_response_line()
  })
}

///|
pub async fn RawSession::finish(self : RawSession) -> Unit {
  if self.finished {
    return
  }
  self.writer.close()
  let exit_code = @async.with_timeout(10000, () => {
    if self.carry.length() > 0 {
      transport_fail("unexpected extra stdout after finish")
    }
    while self.reader.read_some(max_len=4096) is Some(_) {
      transport_fail("unexpected extra stdout after finish")
    }
    self.process.wait()
  })
  if exit_code != 0 {
    transport_fail("control process exit: " + exit_code.to_string())
  }
  self.finished = true
}

///|
pub async fn with_raw(
  executable : String,
  bridge : String,
  capture_path : String,
  body : async (RawSession) -> Unit,
) -> String raise Error {
  let state : Ref[StderrState] = { val: { bytes: [], overflow: false, }, }
  (@async.with_task_group() <| group => {
    let (stdout_reader, stdout_output) = @process.read_from_process()
    let (stderr_reader, stderr_output) = @process.read_from_process()
    let (stdin, stdin_writer) = @process.write_to_process()
    group.add_defer(fn() {
      stdout_reader.close()
      stderr_reader.close()
      stdin_writer.close()
    })
    let env : Map[String, String] = Map([])
    env.set("METONIC_GPU_BRIDGE", bridge)
    env.set("METONIC_CAPTURE_PATH", capture_path)
    let process = @process.spawn(
      group,
      executable,
      [],
      extra_env=env,
      stdin~,
      stdout=stdout_output,
      stderr=stderr_output,
      no_console_window=true,
      no_wait=true,
      cancel_handler=@process.hard_cancel(),
    )
    group.spawn_bg() <| () => { drain_stderr(stderr_reader, state, process) }
    let session : RawSession = {
      reader: stdout_reader,
      writer: stdin_writer,
      process,
      finished: false,
      carry: [],
    }
    errdefer process.cancel()
    body(session)
    if !session.finished {
      session.finish()
    }
  }) catch {
    error => {
      if @async.is_cancellation_error(error) {
        raise error
      }
      raise TransportFailure(
        @debug.to_string(error) +
        "\nstderr: " +
        @utf8.decode_lossy(Bytes::from_array(state.val.bytes)),
      )
    }
  }
  @utf8.decode_lossy(Bytes::from_array(state.val.bytes))
}
