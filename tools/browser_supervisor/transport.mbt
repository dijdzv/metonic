///|
fn tcp_counts(bytes : Bytes, endpoint? : String = "127.0.0.1:4173") -> Json {
  let states : Map[String, Int] = Map([])
  let local_states : Map[String, Int] = Map([])
  for line in @utf8.decode_lossy(bytes).split("\n") {
    let fields = line
      .trim()
      .split(" ")
      .filter(s => s != "")
      .map(s => s.to_owned())
      .to_array()
    if fields.length() != 4 || fields[0] != "TCP" {
      continue
    }
    let state = fields[3]
    if ![
        "LISTENING", "ESTABLISHED", "TIME_WAIT", "CLOSE_WAIT", "SYN_SENT", "SYN_RECEIVED",
        "FIN_WAIT_1", "FIN_WAIT_2", "CLOSING", "LAST_ACK", "DELETE_TCB",
      ].contains(state) {
      continue
    }
    states[state] = states.get(state).unwrap_or(0) + 1
    if fields[1] == endpoint || fields[2] == endpoint {
      local_states[state] = local_states.get(state).unwrap_or(0) + 1
    }
  }
  { "tcp_states": states, "browser_server_states": local_states }
}

///|
async fn collect_tcp_observation(
  endpoint? : String = "127.0.0.1:4173",
  command? : String = "netstat.exe",
  arguments? : Array[String] = ["-an", "-p", "tcp"],
) -> Json {
  let started = @async.now()
  try {
    let counts = @async.with_timeout(1000, () => {
      let (reader, output) = @process.read_from_process()
      defer reader.close()
      defer output.close()
      let (errors, error_output) = @process.read_from_process()
      defer errors.close()
      defer error_output.close()
      // WhyNot: closing a pipe inside the group body can wait on readers
      // before group cancellation has terminated the child that owns its writer.
      @async.with_task_group() <| group => {
        let child = @process.spawn(
          group,
          command,
          arguments,
          stdout=output,
          stderr=error_output,
          no_console_window=true,
          cancel_handler=@process.hard_cancel(),
        )
        let bytes = @ref.new([])
        let discarded = @ref.new([])
        let reading = group.spawn(() => {
          drain(reader, "socket observation", bytes)
        })
        let reading_errors = group.spawn(() => {
          drain(errors, "socket observation stderr", discarded)
        })
        if child.wait() != 0 {
          fail("socket observation failed")
        }
        ignore(reading.wait())
        ignore(reading_errors.wait())
        tcp_counts(Bytes::from_array(bytes.val), endpoint~)
      }
    })
    {
      "status": "available",
      "phase": "after_verifier_report",
      "started_ms": started,
      "elapsed_ms": @async.now() - started,
      "counts": counts,
    }
  } catch {
    _ =>
      {
        "status": "unavailable",
        "phase": "after_verifier_report",
        "started_ms": started,
        "elapsed_ms": @async.now() - started,
      }
  }
}
