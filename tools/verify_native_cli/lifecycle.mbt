///|
suberror LifecycleFailure {
  LifecycleFailure(String)
}

///|
fn fail_lifecycle(message : String) -> Unit raise Error {
  raise LifecycleFailure(message)
}

///|
fn lifecycle_field(value : Json, key : String) -> Json? {
  match value {
    Json::Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn lifecycle_ok(value : Json) -> Bool {
  match lifecycle_field(value, "ok") {
    Some(Json::True) => true
    _ => false
  }
}

///|
async fn lifecycle_capture_exists(root : String) -> Bool {
  for entry in @fs.readdir(root) {
    let child = root + "/" + entry
    if @fs.exists(child + "/capture.rgba") {
      return true
    }
  }
  false
}

///|
async fn lifecycle_case(
  root : String,
  artifact : String,
  cancel : Bool,
) -> Unit raise Error {
  let temp = @fs.tmpdir(prefix="native-cli-lifecycle-")
  defer (@fs.rmdir(temp) catch { _ => () })
  let env : Map[String, String] = Map([])
  env.set("TEMP", temp)
  env.set("TMP", temp)
  @async.with_timeout(20000, () => {
    ignore(
      @async.with_task_group() <| group => {
        let (reader, stdout) = @process.read_from_process()
        let (stdin, writer) = @process.write_to_process()
        group.add_defer(fn() {
          reader.close()
          writer.close()
        })
        let child = group.spawn(() => {
          @process.run(
            @fs.realpath(".tools/moonbit/bin/moonrun.exe"),
            [artifact, "--root", root],
            extra_env=env,
            stdin~,
            stdout~,
            cancel_handler=@process.graceful_cancel(timeout=2000),
          )
        })
        writer.write(b"{\"op\":\"snapshot\"}\n")
        let readiness = @json.parse(reader.read_until("\n").unwrap())
        if !lifecycle_ok(readiness) {
          fail_lifecycle("CLI readiness failed")
        }
        writer.write(b"{\"op\":\"capture\"}\n")
        let capture = @json.parse(reader.read_until("\n").unwrap())
        let capture_response = match lifecycle_field(capture, "response") {
          Some(response) => response
          _ => {
            fail_lifecycle("CLI capture response missing")
            Json::object({})
          }
        }
        if !lifecycle_ok(capture_response) {
          fail_lifecycle("CLI capture failed")
        }
        match lifecycle_field(capture, "image") {
          Some(Json::Object(image)) => {
            match image.get("mimeType") {
              Some(Json::String(mime)) =>
                if mime != "image/png" {
                  fail_lifecycle("CLI capture MIME failed")
                }
              _ => fail_lifecycle("CLI capture MIME missing")
            }
            match image.get("data") {
              Some(Json::String(data)) =>
                if data.length() == 0 {
                  fail_lifecycle("CLI capture data empty")
                }
              _ => fail_lifecycle("CLI capture data missing")
            }
          }
          _ => fail_lifecycle("CLI capture image missing")
        }
        if !lifecycle_capture_exists(temp) {
          fail_lifecycle("CLI capture.rgba missing")
        }
        if cancel {
          child.cancel()
          let _ = child.wait() catch {
            error =>
              if @async.is_cancellation_error(error) {
                -1
              } else {
                raise error
              }
          }
        } else {
          writer.close()
          let exit_code = child.wait()
          if exit_code != 0 {
            fail_lifecycle("CLI EOF exit code was not zero")
          }
        }
      },
    )
    ()
  })
  if @fs.readdir(temp).length() != 0 {
    fail_lifecycle("CLI temp directory was not empty")
  }
}

///|
pub async fn check_lifecycle(root : String) -> Unit {
  let artifact = root +
    "/_build/wasm/release/build/tools/native_cli/native_cli.wasm"
  lifecycle_case(root, artifact, false)
  lifecycle_case(root, artifact, true)
}
