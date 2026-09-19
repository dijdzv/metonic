///|
let runtime_files : Array[String] = [
  "window_app.exe", "accesskit.dll", "ACCESSKIT-LICENSE-MIT", "ACCESSKIT-LICENSE-APACHE",
]

///|
async fn remove_runtime(directory : String) -> Unit {
  for name in runtime_files {
    let path = directory + "/" + name
    if @fs.exists(path) {
      @fs.remove(path)
    }
  }
  // Nonrecursive removal cannot silently delete unexpected files.
  @fs.rmdir(directory)
}

///|
async fn stage_runtime(source : String) -> String {
  let directory = @fs.tmpdir(prefix="metonic-demo-runtime")
  errdefer @async.protect_from_cancel(() => {
    remove_runtime(directory) catch {
      cleanup =>
        println(
          "Demo runtime cleanup failed: " +
          directory +
          ": " +
          cleanup.to_string(),
        )
    }
  })
  for name in runtime_files {
    @fs.write_file(directory + "/" + name, @fs.read_file(source + "/" + name))
  }
  directory
}

///|
async fn with_runtime(source : String, run : async (String) -> Unit) -> Unit {
  let directory = stage_runtime(source)
  defer @async.protect_from_cancel(() => {
    remove_runtime(directory) catch {
      error =>
        println(
          "Demo runtime retained: " + directory + ": " + error.to_string(),
        )
    }
  })
  println("Native runtime: " + directory + "/window_app.exe")
  println("Native build source: " + @fs.realpath(source))
  run(directory + "/window_app.exe")
}
