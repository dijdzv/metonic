///|
///  Browser verification supervisor. It owns both verifier and server processes.
suberror SupervisorFailure {
  Failure(String)
} derive(Debug)

///|
fn fail(message : String) -> Unit raise Error {
  raise SupervisorFailure::Failure(message)
}

///|
fn windows_tree_cancel(
  warning : @ref.Ref[String?],
) -> @process.CancellationHandler {
  @process.CancellationHandler(async fn(pid) {
    @async.protect_from_cancel() <| () => {
      let status = @async.with_timeout(5000, async fn() {
        let (status, _, _) = @process.collect_output(
          "taskkill.exe",
          ["/PID", pid.to_string(), "/T", "/F"],
          no_console_window=true,
        )
        status
      }) catch {
        _ => {
          warning.val = Some("taskkill threw; hard cancel fallback used")
          -1
        }
      }
      if status != 0 {
        warning.val = Some(
          "taskkill returned nonzero; hard cancel fallback used",
        )
        let fallback = @process.hard_cancel()
        fallback(pid)
      }
    }
  })
}

///|
async fn save_logs(
  out : String,
  server : @ref.Ref[Array[Byte]],
  server_err : @ref.Ref[Array[Byte]],
  verifier : @ref.Ref[Array[Byte]],
  verifier_err : @ref.Ref[Array[Byte]],
  result : String,
) -> Unit {
  @fs.write_file(out + "/server.stdout.log", Bytes::from_array(server.val))
  @fs.write_file(out + "/server.stderr.log", Bytes::from_array(server_err.val))
  @fs.write_file(out + "/verifier.stdout.log", Bytes::from_array(verifier.val))
  @fs.write_file(
    out + "/verifier.stderr.log",
    Bytes::from_array(verifier_err.val),
  )
  @fs.write_file(out + "/result.json", @utf8.encode(result))
}

///|
fn warning_json(warning : @ref.Ref[String?]) -> Json {
  match warning.val {
    Some(value) => Json::string(value)
    None => Json::null()
  }
}

///|
async fn drain(
  reader : @process.ReadFromProcess,
  label : String,
  capture : @ref.Ref[Array[Byte]],
) -> Int raise Error {
  defer reader.close()
  let prefix = capture.val
  let mut total = prefix.length()
  while true {
    let chunk = reader.read_some(max_len=4096)
    match chunk {
      None => return total
      Some(bytes) => {
        total += bytes.length()
        for byte in bytes {
          if prefix.length() < 65536 {
            prefix.push(byte)
          }
        }
        capture.val = prefix
        if total > 65536 {
          fail(label + " output overflow")
        }
      }
    }
  } nobreak {
    total
  }
}

///|
async fn run_session(
  mode : String,
  server_command : String,
  server_args : Array[String],
  verifier_command : String,
  verifier_args : Array[String],
  deadline_ms : Int,
  readiness_ms? : Int = 10000,
  fault_server? : Bool = false,
  server_capture~ : @ref.Ref[Array[Byte]],
  server_err_capture~ : @ref.Ref[Array[Byte]],
  verifier_capture~ : @ref.Ref[Array[Byte]],
  verifier_err_capture~ : @ref.Ref[Array[Byte]],
  cleanup_capture? : @ref.Ref[String?] = @ref.new(None),
) -> Unit raise Error {
  if mode != "async" && mode != "headless" {
    fail("invalid mode")
  }
  let (server_reader, server_stdout) = @process.read_from_process()
  defer server_reader.close()
  defer server_stdout.close()
  let (server_err_reader, server_stderr) = @process.read_from_process()
  defer server_err_reader.close()
  defer server_stderr.close()
  let (verifier_reader, verifier_stdout) = @process.read_from_process()
  defer verifier_reader.close()
  defer verifier_stdout.close()
  let (verifier_err_reader, verifier_stderr) = @process.read_from_process()
  defer verifier_stderr.close()
  defer verifier_err_reader.close()
  @async.with_timeout(deadline_ms, async fn() {
    @async.with_task_group(async fn(group) {
      let server = @process.spawn(
        group,
        server_command,
        server_args,
        stdout=server_stdout,
        stderr=server_stderr,
        no_console_window=true,
        no_wait=false,
        cancel_handler=@process.hard_cancel(),
      )
      defer server.cancel()
      ignore(
        group.spawn(() => {
          drain(server_err_reader, "server stderr", server_err_capture)
        }),
      )
      let expected = b"http://127.0.0.1:4173/\n"
      let ready = @async.with_timeout(readiness_ms, async fn() {
        server_reader.read_exactly(expected.length())
      })
      for byte in ready {
        if server_capture.val.length() < 65536 {
          server_capture.val.push(byte)
        }
      }
      if ready != expected {
        fail("invalid browser server readiness")
      }
      server_capture.val = expected.to_array()
      let expected_shutdown = @ref.new(false)
      ignore(
        group.spawn(() => {
          let status = server.wait() catch {
            error =>
              if expected_shutdown.val && @async.is_cancellation_error(error) {
                -1
              } else {
                raise error
              }
          }
          if !expected_shutdown.val {
            fail("browser server exited early: " + status.to_string())
          }
        }),
      )
      ignore(
        group.spawn(() => drain(server_reader, "server stdout", server_capture)),
      )
      let verifier_env = Map([("METONIC_BROWSER_SUPERVISED", "1")])
      let (fault_reader, fault_stdout) = @process.read_from_process()
      defer fault_reader.close()
      defer fault_stdout.close()
      let fault = if fault_server {
        Some(
          @process.spawn(
            group,
            ".tools/moonbit/bin/moonrun.exe",
            [
              "_build/wasm/release/build/tools/rpc_fault_server/rpc_fault_server.wasm",
            ],
            stdout=fault_stdout,
            no_console_window=true,
            cancel_handler=@process.hard_cancel(),
          ),
        )
      } else {
        None
      }
      defer (if fault is Some(child) { child.cancel() })
      if fault is Some(_) {
        let line = @async.with_timeout(10000, () => {
          fault_reader.read_until("\n").unwrap().trim().to_owned()
        })
        if !line.has_prefix("RPC_FAULT_READY 127.0.0.1:") {
          fail("invalid fault server readiness")
        }
        verifier_env.set(
          "METONIC_RPC_FIXTURE",
          "http://" + line[16:].to_owned(),
        )
      }
      let verifier = @process.spawn(
        group,
        verifier_command,
        verifier_args,
        stdout=verifier_stdout,
        stderr=verifier_stderr,
        extra_env=verifier_env,
        no_console_window=true,
        cancel_handler=windows_tree_cancel(cleanup_capture),
      )
      ignore(
        group.spawn(() => {
          drain(verifier_reader, "verifier stdout", verifier_capture)
        }),
      )
      ignore(
        group.spawn(() => {
          drain(verifier_err_reader, "verifier stderr", verifier_err_capture)
        }),
      )
      let verifier_status = verifier.wait()
      if verifier_status != 0 {
        fail("verifier exited with code " + verifier_status.to_string())
      }
      expected_shutdown.val = true
      server.cancel()
      let server_status = server.wait() catch {
        error =>
          if @async.is_cancellation_error(error) {
            -1
          } else {
            raise error
          }
      }
      ignore(server_status)
    })
  })
}

///|
#warnings("-fragile_catch_all")
async fn main {
  let args = @env.args()
  guard args.length() == 2 else {
    fail("usage: browser_supervisor.wasm async|headless")
  }
  let mode = args[1]
  if mode != "async" && mode != "headless" {
    fail("invalid mode")
  }
  let verifier = if mode == "async" {
    "scripts/verify-browser-async.mjs"
  } else {
    "scripts/verify-browser-headless.mjs"
  }
  let backend = match @env.get_env_var("METONIC_GPU_BACKEND") {
    Some(value) if value == "swiftshader" || value == "default" => value
    None => "default"
    _ => {
      fail("invalid GPU backend")
      ""
    }
  }
  let out = ".work/browser-supervisor/" + mode + "/" + backend
  if !@fs.exists(out) {
    @fs.mkdir(out, recursive=true)
  }
  let server_capture = @ref.new([])
  let server_err_capture = @ref.new([])
  let verifier_capture = @ref.new([])
  let verifier_err_capture = @ref.new([])
  let cleanup_capture : @ref.Ref[String?] = @ref.new(None)
  run_session(
    mode,
    ".tools/moonbit/bin/moonrun.exe",
    ["_build/wasm/release/build/tools/browser_server/browser_server.wasm"],
    "node",
    [verifier],
    300000,
    fault_server=mode == "headless",
    server_capture~,
    server_err_capture~,
    verifier_capture~,
    verifier_err_capture~,
    cleanup_capture~,
  ) catch {
    error => {
      save_logs(
        out,
        server_capture,
        server_err_capture,
        verifier_capture,
        verifier_err_capture,
        Json::object({
          "outcome": Json::string("failure"),
          "error": Json::string(error.to_string()),
          "cleanup_warning": warning_json(cleanup_capture),
        }).stringify(),
      )
      raise error
    }
  }
  @fs.write_file(
    out + "/server.stdout.log",
    Bytes::from_array(server_capture.val),
  )
  @fs.write_file(
    out + "/server.stderr.log",
    Bytes::from_array(server_err_capture.val),
  )
  @fs.write_file(
    out + "/verifier.stdout.log",
    Bytes::from_array(verifier_capture.val),
  )
  @fs.write_file(
    out + "/verifier.stderr.log",
    Bytes::from_array(verifier_err_capture.val),
  )
  @fs.write_file(
    out + "/result.json",
    @utf8.encode(
      Json::object({
        "outcome": Json::string("success"),
        "cleanup_warning": warning_json(cleanup_capture),
      }).stringify(),
    ),
  )
}
