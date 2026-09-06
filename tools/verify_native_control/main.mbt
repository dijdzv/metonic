///|
suberror VerifyFailure {
  VerifyFailure(String)
}

///|
fn fail(message : String) -> Unit raise Error {
  println("native control verification failed: " + message)
  raise VerifyFailure(message)
}

///|
fn require(condition : Bool, message : String) -> Unit raise Error {
  if !condition {
    fail(message)
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
fn bool_field(object : Json, key : String) -> Bool raise Error {
  match field(object, key) {
    Some(Json::True) => true
    Some(Json::False) => false
    _ => {
      fail("missing boolean field " + key)
      false
    }
  }
}

///|
fn int_field(object : Json, key : String) -> Int raise Error {
  match field(object, key) {
    Some(Json::Number(value, ..)) => value.to_int()
    _ => {
      fail("missing integer field " + key)
      0
    }
  }
}

///|
fn state_array(response : Json) -> Array[Json] raise Error {
  match field(response, "state") {
    Some(Json::Array(values)) => values
    _ => {
      fail("missing state")
      []
    }
  }
}

///|
fn state_int(state : Array[Json], index : Int) -> Int raise Error {
  match state[index] {
    Json::Number(value, ..) => value.to_int()
    _ => {
      fail("invalid state")
      0
    }
  }
}

///|
fn pixel_assert(
  rgba : Bytes,
  response : Json,
  active : Bool,
) -> Unit raise Error {
  let state = state_array(response)
  let width = state_int(state, 6)
  let height = state_int(state, 7)
  require(rgba.length() == width * height * 4, "RGBA length")
  let x0 = state_int(state, 0)
  let y0 = state_int(state, 1)
  let rw = state_int(state, 2)
  let rh = state_int(state, 3)
  let fg = if active { [242, 97, 26, 255] } else { [20, 166, 173, 255] }
  let mut i = 0
  while i < rgba.length() {
    let pixel = i / 4
    let x = pixel % width
    let y = pixel / width
    let expected = if x >= x0 && x < x0 + rw && y >= y0 && y < y0 + rh {
      fg
    } else {
      [5, 20, 38, 255]
    }
    let mut c = 0
    while c < 4 {
      require((rgba[i + c].to_int() - expected[c]).abs() <= 1, "pixel mismatch")
      c += 1
    }
    i += 4
  }
}

///|
async fn capture_attempt(client : @control.Client, revision : Int) -> String {
  ignore(client.capture(expected_revision=Some(revision))) catch {
    error => return "error:" + @debug.to_string(error)
  }
  "ok"
}

///|
async fn main {
  let mode = if @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1") {
    "fallback"
  } else {
    "default"
  }
  let root = @fs.realpath(".")
  let result_dir = root + "/.work/native-control"
  if !@fs.exists(result_dir) {
    @fs.mkdir(result_dir, recursive=true)
  }
  let session = @fs.tmpdir(prefix="native-control-")
  let capture_path = session + "/capture.rgba"
  defer {
    if @fs.exists(capture_path) {
      @fs.remove(capture_path) catch {
        error => println("capture cleanup failed: " + @debug.to_string(error))
      }
    }
    @fs.rmdir(session) catch {
      error => println("session cleanup failed: " + @debug.to_string(error))
    }
  }
  let result_path = result_dir + "/" + mode + ".json"
  let exe = root +
    "/_build/native/release/build/examples/p0/native_headless/native_headless.exe"
  let bridge = root + "/.work/native-cargo/release/metonic_wgpu_probe.dll"
  let config = @control.Config::new(exe, [], bridge, capture_path, 15000, 16)
  let checks : Array[Json] = []
  let mut adapter = Json::object({})
  let mut failure : String? = None
  @control.with_client(config, async fn(client) {
    adapter = client.diagnostics()
    defer {
      adapter = client.diagnostics()
    }
    let snapshot = client.request("snapshot")
    require(bool_field(snapshot, "ok"), "snapshot")
    require(int_field(snapshot, "frame") == 0, "initial frame")
    let initial = state_array(snapshot)
    let moved = client.request(
      "move",
      args=Json::object({
        "x": Json::number(10.0),
        "y": Json::number(20.0),
        "expected_revision": Json::number(state_int(initial, 5).to_double()),
      }),
    )
    require(bool_field(moved, "ok"), "move")
    require(
      state_int(state_array(moved), 0) == 10 &&
      state_int(state_array(moved), 1) == 20,
      "move position",
    )
    let activated = client.request(
      "activate",
      args=Json::object({
        "expected_revision": Json::number(
          state_int(state_array(moved), 5).to_double(),
        ),
      }),
    )
    require(bool_field(activated, "ok"), "activate")
    require(state_int(state_array(activated), 4) == 1, "active state")
    let captured = client.capture(
      expected_revision=Some(state_int(state_array(activated), 5)),
    )
    require(int_field(captured.0, "frame") == 1, "capture frame")
    require(
      state_int(state_array(captured.0), 0) == 10 &&
      state_int(state_array(captured.0), 1) == 20,
      "capture position",
    )
    pixel_assert(captured.1, captured.0, true)
    let image = @image.ImageData::{
      width: state_int(state_array(captured.0), 6),
      height: state_int(state_array(captured.0), 7),
      data: captured.1,
    }
    @fs.write_file(result_dir + "/" + mode + ".png", @image.encode_png(image))
    checks.push(Json::string("snapshot/move/activate/capture/pixels"))
    let stable = state_array(captured.0)
    let stale = client.request(
      "move",
      args=Json::object({
        "x": Json::number(0.0),
        "y": Json::number(0.0),
        "expected_revision": Json::number(
          (state_int(stable, 5) - 1).to_double(),
        ),
      }),
    )
    require(!bool_field(stale, "ok"), "stale move rejected")
    require(
      field(stale, "error") == Some(Json::string("stale_revision")),
      "stale move error",
    )
    require(state_array(stale) == stable, "stale state unchanged")
    let stale_capture = capture_attempt(client, state_int(stable, 5) - 1)
    require(stale_capture.contains("stale_revision"), "stale capture error")
    checks.push(Json::string("stale mutation/capture"))
    @async.with_task_group() <| group => {
      let first = group.spawn(() => {
        capture_attempt(client, state_int(stable, 5))
      })
      let second = group.spawn(() => {
        capture_attempt(client, state_int(stable, 5))
      })
      let one = first.wait()
      let two = second.wait()
      require(
        (one == "ok" && two.contains("capture already in progress")) ||
        (two == "ok" && one.contains("capture already in progress")),
        "capture busy serialization",
      )
    }
    checks.push(Json::string("capture busy serialization"))
    client.close()
  }) catch {
    error => failure = Some(@debug.to_string(error))
  }
  let output = match failure {
    Some(error) =>
      Json::object({
        "mode": Json::string(mode),
        "ok": Json::boolean(false),
        "error": Json::string(error),
        "checks": Json::array(checks),
        "adapter": adapter,
      })
    None =>
      Json::object({
        "mode": Json::string(mode),
        "ok": Json::boolean(true),
        "checks": Json::array(checks),
        "adapter": adapter,
      })
  }
  match failure {
    Some(_) =>
      @fs.write_file(result_path, output.stringify()) catch {
        error =>
          println("failure result write failed: " + @debug.to_string(error))
      }
    None => @fs.write_file(result_path, output.stringify())
  }
  println(output.stringify())
  match failure {
    Some(error) => abort(error)
    None => ()
  }
}
