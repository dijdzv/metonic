///|
#unsafe_skip_stub_check
fn runtime_exit(code : Int) = "moonbitlang/async" "runtime/exit"

///|
async fn log_directory(lane : String) -> String {
  let root = ".work/hook-logs"
  @fs.mkdir(root, recursive=true) catch {
    error => if !@fs.exists(root) { raise error }
  }
  for attempt in 0..<100 {
    let path = root +
      "/" +
      lane +
      "-" +
      @env.now().to_string() +
      "-" +
      attempt.to_string()
    try {
      @fs.mkdir(path)
      return path
    } catch {
      error => if !@fs.exists(path) { raise error }
    }
  }
  abort("cannot reserve hook log directory")
}

///|
async fn log_tail(path : String) -> (String, Bool) {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  let count = if size > 65536L { 65536 } else { size.to_int() }
  let bytes = file.read_exactly_at(count, position=size - count.to_int64())
  (@utf8.decode_lossy(bytes), size > 65536L)
}

///|
async fn run_logged(
  command : String,
  arguments : Array[String],
  path : String,
) -> Int {
  let log = @fs.open(path, mode=WriteOnly, create_mode=CreateOrTruncate)
  defer log.close()
  let (reader, output) = @process.read_from_process()
  defer reader.close()
  defer output.close()
  @async.with_task_group(async fn(group) {
    let process = @process.spawn(
      group,
      command,
      arguments,
      stdin=@stdio.stdin,
      stdout=output,
      stderr=output,
      no_console_window=true,
      no_wait=false,
    )
    output.close()
    let progress = Progress::new()
    while reader.read_some(max_len=8192) is Some(bytes) {
      @io.Writer::write(log, bytes)
      for message in progress.feed(bytes) {
        println(message)
      }
    }
    process.wait()
  })
}

///|
async fn main {
  let args = @env.args()
  guard args.length() >= 2 && (args[1] == "commit" || args[1] == "push") else {
    println("hook verification failed: expected commit or push")
    runtime_exit(2)
    return
  }
  let lane = args[1]
  let started = @async.now()
  let mut log : String? = None
  try {
    let directory = log_directory(lane)
    let path = directory + "/output.log"
    log = Some(path)
    println("pre-" + lane + " started; discovering verification inputs.")
    let script = if lane == "commit" {
      "scripts/record-commit-verification.mbtx"
    } else {
      "scripts/verify-push-recorded.mbtx"
    }
    let command_args = ["run", script]
    if args.length() > 2 {
      command_args.push("--")
      for arg in args[2:] {
        command_args.push(arg)
      }
    }
    let status = run_logged(".tools/moonbit/bin/moon.exe", command_args, path)
    let elapsed = (@async.now() - started).to_int().to_string()
    if status == 0 {
      println("pre-" + lane + " passed (" + elapsed + " ms). Log: " + path)
    } else {
      println(
        "pre-" +
        lane +
        " failed (exit " +
        status.to_string() +
        "). Log: " +
        path,
      )
      let (tail, truncated) = log_tail(path)
      println(failure_output(tail, truncated~))
    }
    runtime_exit(status)
  } catch {
    error => {
      println("pre-" + lane + " infrastructure failure: " + error.to_string())
      if log is Some(path) {
        println("Log: " + path)
      }
      runtime_exit(1)
    }
  }
}
