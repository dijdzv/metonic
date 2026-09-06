///|
/// A small, line-oriented client for the native control probe.
pub struct Config {
  executable : String
  args : Array[String]
  bridge : String
  capture_path : String
  timeout_ms : Int
  max_pending : Int
}

///|
pub fn Config::new(
  executable : String,
  args : Array[String],
  bridge : String,
  capture_path : String,
  timeout_ms : Int,
  max_pending : Int,
) -> Config {
  { executable, args, bridge, capture_path, timeout_ms, max_pending, }
}

///|
struct ClientState {
  mut closed : Bool
  mut closing : Bool
  mut close_done : Bool
  close_cond : @cond_var.Cond
  mut next_id : Int64
  mut pending : Int
  mut capture_busy : Bool
  pending_map : Map[Int, Ref[Pending]]
}

///|
priv struct Pending {
  cond : @cond_var.Cond
  mut result : Json?
  mut error : String?
}

///|
pub struct Client {
  config : Config
  process : @process.Process
  reader : @process.ReadFromProcess
  writer : @process.WriteToProcess
  mutex : @async.Mutex
  state : ClientState
  mut stderr_tail : Array[Byte]
}

///|
priv suberror ClientError {
  Failure(String)
} derive(Debug)

///|
fn[T] fail(message : String) -> T raise {
  raise Failure(message)
}

///|
fn absolute(path : String) -> Bool {
  if path.length() >= 3 && path[1] == ':' && (path[2] == '/' || path[2] == '\\') {
    true
  } else if path.length() >= 2 && path[0] == '\\' && path[1] == '\\' {
    true
  } else if path.length() > 0 && path[0] == '/' {
    true
  } else {
    false
  }
}

///|
fn validate_config(config : Config) -> Unit raise {
  if !absolute(config.executable) {
    fail("executable must be absolute")
  }
  if !absolute(config.bridge) {
    fail("bridge must be absolute")
  }
  if !absolute(config.capture_path) {
    fail("capture_path must be absolute")
  }
  if config.timeout_ms <= 0 {
    fail("timeout_ms must be positive")
  }
  if config.max_pending <= 0 {
    fail("max_pending must be positive")
  }
}

///|
fn field(object : Json, key : String) -> Json? {
  match object {
    Json::Object(values) => values.get(key)
    _ => None
  }
}

///|
async fn stdout_loop(client : Client) -> Unit {
  let lines = @wire.WireLines::new()
  while !client.state.closed {
    try {
      match client.reader.read_some(max_len=4096) {
        None => fatal(client, "control process exited")
        Some(chunk) =>
          for line in lines.feed(chunk) {
            let (id, response) = @wire.wire_response(line)
            match client.state.pending_map.get(id) {
              Some(pending) => {
                client.state.pending_map.remove(id)
                pending.val.result = Some(response)
                pending.val.cond.signal()
              }
              None => fatal(client, "unknown response id")
            }
          }
      }
    } catch {
      error =>
        if @async.is_cancellation_error(error) {
          raise error
        } else {
          fatal(
            client,
            "malformed control response: " + @debug.to_string(error),
          )
        }
    }
  }
}

///|
fn fatal(client : Client, message : String) -> Unit {
  client.state.closed = true
  client.process.cancel()
  for _, pending in client.state.pending_map {
    pending.val.error = Some(message)
    pending.val.cond.broadcast()
  }
  client.state.pending_map.clear()
}

///|
async fn send_line(client : Client, payload : String) -> Unit {
  client.mutex.acquire()
  defer client.mutex.release()
  client.writer.write(payload + "\n")
}

///|
async fn stderr_loop(
  client : Client,
  reader : @process.ReadFromProcess,
) -> Unit {
  while !client.state.closed {
    match reader.read_some(max_len=4096) {
      None => break
      Some(chunk) => {
        let old_len = client.stderr_tail.length()
        let chunk_len = chunk.length()
        let overflow = old_len + chunk_len - 16384
        if overflow > 0 {
          let retained : Array[Byte] = []
          let start_old = if overflow < old_len { overflow } else { old_len }
          for i = start_old; i < old_len; i = i + 1 {
            retained.push(client.stderr_tail[i])
          }
          let start_chunk = if overflow > old_len {
            overflow - old_len
          } else {
            0
          }
          for i = start_chunk; i < chunk_len; i = i + 1 {
            retained.push(chunk[i])
          }
          client.stderr_tail = retained
        } else {
          for byte in chunk.iter() {
            client.stderr_tail.push(byte)
          }
        }
      }
    }
  }
}

///|
async fn Client::request_inner(
  self : Client,
  op : String,
  args : Json,
  internal_capture : Bool,
  allow_closing : Bool,
) -> Json {
  @async.sleep(0)
  if self.state.closed || (self.state.closing && !allow_closing) {
    fail("client is closed")
  }
  if op.length() == 0 {
    fail("operation must be non-empty")
  }
  if self.state.pending >= self.config.max_pending {
    fail("pending request limit exceeded")
  }
  if self.state.next_id > 2147483647L {
    fail("request id exhausted")
  }
  let id = self.state.next_id.to_int()
  self.state.next_id = self.state.next_id + 1L
  self.state.pending += 1
  defer {
    self.state.pending = self.state.pending - 1
  }
  let payload = @wire.wire_request(id, op, args, internal_capture)
  let pending : Ref[Pending] = {
    val: { cond: @cond_var.Cond::Cond(), result: None, error: None, },
  }
  self.state.pending_map.set(id, pending)
  errdefer fatal(self, "request write failed")
  let completed = @async.with_timeout_opt(self.config.timeout_ms, () => {
    send_line(self, payload)
    while pending.val.result is None && pending.val.error is None {
      pending.val.cond.wait()
    }
    ()
  })
  match completed {
    None => {
      fatal(self, "request timed out")
      fail("request timed out")
    }
    Some(_) =>
      match pending.val.error {
        Some(error) => fail(error)
        None => pending.val.result.unwrap()
      }
  }
}

///|
pub async fn Client::request(
  self : Client,
  op : String,
  args? : Json = Json::object({}),
) -> Json {
  self.request_inner(op, args, false, false)
}

///|
pub async fn Client::capture(
  self : Client,
  expected_revision? : Int? = None,
) -> (Json, Bytes) {
  if self.state.capture_busy {
    fail("capture already in progress")
  }
  self.state.capture_busy = true
  defer {
    self.state.capture_busy = false
  }
  let args : Json = match expected_revision {
    Some(value) =>
      Json::object({ "expected_revision": Json::number(value.to_double()) })
    None => Json::object({})
  }
  let response = self.request_inner("capture", args, true, false)
  match field(response, "ok") {
    Some(Json::True) => ()
    Some(Json::False) =>
      match field(response, "error") {
        Some(Json::String(message)) => fail(message)
        _ => fail("capture rejected")
      }
    _ => fail("capture response missing ok")
  }
  let state = match field(response, "state") {
    Some(Json::Array(values)) => values
    _ => {
      fail("capture state")
      []
    }
  }
  let width = match state[6] {
    Json::Number(value, ..) => value.to_int()
    _ => {
      fail("capture width")
      0
    }
  }
  let height = match state[7] {
    Json::Number(value, ..) => value.to_int()
    _ => {
      fail("capture height")
      0
    }
  }
  let data = @fs.read_file(self.config.capture_path)
  let bytes = data.binary()
  if bytes.length() != width * height * 4 {
    fail("capture size mismatch")
  }
  (response, bytes)
}

///|
pub async fn Client::close(self : Client) -> Unit {
  @async.sleep(0)
  if self.state.close_done {
    return
  }
  if self.state.closing {
    while !self.state.close_done {
      self.state.close_cond.wait()
    }
    return
  }
  self.state.closing = true
  defer {
    self.state.close_done = true
    self.state.close_cond.broadcast()
  }
  @async.protect_from_cancel() <| () => {
    let completed = @async.with_timeout_opt(2000, () => {
      ignore(self.request_inner("shutdown", Json::object({}), true, true)) catch {
        _ => ()
      }
      self.writer.close()
    })
    match completed {
      None => self.process.cancel()
      Some(_) => ()
    }
  }
  self.process.cancel()
  fatal(self, "client closed")
}

///|
pub fn Client::diagnostics(self : Client) -> Json {
  Json::object({
    "stderr": Json::string(
      @utf8.decode_lossy(Bytes::from_array(self.stderr_tail)),
    ),
    "closed": Json::boolean(self.state.closed),
    "pending": Json::number(self.state.pending.to_double()),
  })
}

///|
pub async fn with_client(
  config : Config,
  action : async (Client) -> Unit,
) -> Unit {
  validate_config(config)
  @async.with_task_group() <| group => {
    let (reader, stdout) = @process.read_from_process()
    let (stdin, writer) = @process.write_to_process()
    let (stderr_reader, stderr_output) = @process.read_from_process()
    group.add_defer(fn() {
      writer.close()
      reader.close()
      stderr_reader.close()
    })
    let env : Map[String, String] = Map([])
    env.set("METONIC_GPU_BRIDGE", config.bridge)
    env.set("METONIC_CAPTURE_PATH", config.capture_path)
    let process = @process.spawn(
      group,
      config.executable,
      config.args,
      extra_env=env,
      stdin~,
      stdout~,
      stderr=stderr_output,
      no_console_window=true,
      no_wait=true,
      cancel_handler=@process.hard_cancel(),
    )
    let client : Client = {
      config,
      process,
      reader,
      writer,
      mutex: @async.Mutex::Mutex(),
      state: {
        closed: false,
        closing: false,
        close_done: false,
        close_cond: @cond_var.Cond::Cond(),
        next_id: 1L,
        pending: 0,
        capture_busy: false,
        pending_map: Map([]),
      },
      stderr_tail: [],
    }
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      stdout_loop(client)
    }
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      stderr_loop(client, stderr_reader)
    }
    defer process.cancel()
    action(client)
    client.close()
  }
}
