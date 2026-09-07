///|
/// Preserve fixture exit statuses in the Wasm runtime.
#unsafe_skip_stub_check
fn runtime_exit(code : Int) = "moonbitlang/async" "runtime/exit"

///|
async fn[W : @io.Writer] write_bytes_all(output : W, data : Bytes) -> Unit {
  let mut offset = 0
  while offset < data.length() {
    let written = output.write_once(data, offset~, len=data.length() - offset)
    if written <= 0 {
      return
    }
    offset += written
  }
}

///|
async fn write_stdout(value : String) -> Unit {
  write_bytes_all(@stdio.stdout, @utf8.encode(value))
}

///|
async fn write_stderr(value : String) -> Unit {
  write_bytes_all(@stdio.stderr, @utf8.encode(value))
}

///|
fn known_mode(mode : String) -> Bool {
  mode == "server-ready" ||
  mode == "server-bad" ||
  mode == "server-silent" ||
  mode == "server-exit" ||
  mode == "verifier-ok" ||
  mode == "verifier-fail" ||
  mode == "verifier-overflow" ||
  mode == "verifier-hang" ||
  mode == "verifier-tree" ||
  mode == "sleep-child"
}

///|
async fn main {
  let args = @env.args()
  guard args is [_, mode] else {
    abort("usage: browser_supervisor_fixture.wasm MODE")
  }
  guard known_mode(mode) else { abort("unknown fixture mode") }

  if mode == "server-ready" {
    write_stdout("http://127.0.0.1:4173/\n")
    @async.sleep(300000)
  } else if mode == "server-bad" {
    write_stdout("http://127.0.0.1:4174/\n")
    @async.sleep(300000)
  } else if mode == "server-silent" {
    @async.sleep(300000)
  } else if mode == "server-exit" {
    write_stdout("http://127.0.0.1:4173/\n")
    @async.sleep(200)
    runtime_exit(7)
  } else if mode == "verifier-ok" {
    write_stdout("FIXTURE_OK\n")
    write_stderr("FIXTURE_DIAGNOSTIC\n")
    runtime_exit(0)
  } else if mode == "verifier-fail" {
    runtime_exit(7)
  } else if mode == "verifier-overflow" {
    for _ in 0..<18 {
      write_bytes_all(@stdio.stdout, Bytes::make(4096, b'x'))
    }
    @async.sleep(300000)
  } else if mode == "verifier-hang" {
    @async.sleep(300000)
  } else if mode == "verifier-tree" {
    let child = @process.spawn_orphan(
      ".tools/moonbit/bin/moonrun.exe",
      [
        "_build/wasm/release/build/tools/browser_supervisor_fixture/browser_supervisor_fixture.wasm",
        "sleep-child",
      ],
      cwd=".",
      no_console_window=true,
    )
    let alive = @async.with_timeout_opt(50, () => @process.wait_pid(child))
    if alive is Some(_) {
      abort("tree child exited before timeout")
    }
    write_stdout("CHILD_PID=" + child.to_string() + "\nCHILD_ALIVE=1\n")
    @async.sleep(300000)
  } else {
    // `sleep-child` is intentionally side-effect free: tree cleanup relies on
    // the child being a leaf process.
    @async.sleep(300000)
  }
}
