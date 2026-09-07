///|
suberror DemoFailure {
  Failure(String)
} derive(Debug)

///|
async fn run_session(
  server_command : String,
  server_args : Array[String],
  native_command : String,
  native_args : Array[String],
  readiness_ms? : Int = 10000,
) -> Unit {
  let (reader, stdout) = @process.read_from_process()
  defer reader.close()
  defer stdout.close()
  @async.with_task_group(group => {
    let server = @process.spawn(
      group,
      server_command,
      server_args,
      stdout~,
      no_console_window=true,
      cancel_handler=@process.hard_cancel(),
    )
    defer server.cancel()
    let expected = b"http://127.0.0.1:4173/\n"
    let ready = @async.with_timeout(readiness_ms, () => {
      reader.read_exactly(expected.length())
    })
    guard ready == expected else {
      raise DemoFailure::Failure("unexpected demo server address")
    }
    let native = @process.spawn(
      group,
      native_command,
      native_args,
      extra_env=Map([("METONIC_RPC_BASE", "http://127.0.0.1:4173")]),
      no_console_window=true,
      cancel_handler=@process.hard_cancel(),
    )
    defer native.cancel()
    println("Web: http://127.0.0.1:4173/ (WasmGC; JS comparison: ?target=js)")
    println("Native: edit text; F7 lookup, F5 delayed move, F6 cancel.")
    println("Close the native window to stop this demo and its HTTP server.")
    while native.try_wait() is None {
      if server.try_wait() is Some(status) {
        raise DemoFailure::Failure("demo server exited: " + status.to_string())
      }
      @async.sleep(25)
    }
    let status = native.wait()
    guard status == 0 else {
      raise DemoFailure::Failure("native window exited: " + status.to_string())
    }
  })
  println("DEMO_STOPPED")
}

///|
async fn main {
  run_session(
    ".tools/moonbit/bin/moonrun.exe",
    ["_build/wasm/release/build/tools/browser_server/browser_server.wasm"],
    ".work/native-host-build/native/release/build/local/native_host/window_app/window_app.exe",
    [],
  )
}
