///|
suberror VerifyFailure {
  VerifyFailure(String)
} derive(Debug)

///|
fn fail(message : String) -> Unit raise Error {
  raise VerifyFailure(message)
}

///|
fn require(value : Bool, message : String) -> Unit raise Error {
  if !value {
    fail(message)
  }
}

///|
fn is_true(value : Json, message : String) -> Unit raise Error {
  require(field(value, "ok") == Some(Json::boolean(true)), message)
}

///|
fn field(value : Json, key : String) -> Json? {
  match value {
    Json::Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn number(value : Json, key : String) -> Int raise Error {
  match field(value, key) {
    Some(Json::Number(number, ..)) if number.to_int().to_double() == number =>
      number.to_int()
    _ => {
      fail("missing integer " + key)
      0
    }
  }
}

///|
fn state(value : Json) -> Array[Json] raise Error {
  match field(value, "state") {
    Some(Json::Array(values)) => values
    _ => {
      fail("missing state")
      []
    }
  }
}

///|
fn state_number(values : Array[Json], index : Int) -> Int raise Error {
  match values[index] {
    Json::Number(value, ..) if value.to_int().to_double() == value =>
      value.to_int()
    _ => {
      fail("invalid state")
      0
    }
  }
}

///|
fn assert_meta(value : Json, id : Int, message : String) -> Unit raise Error {
  require(number(value, "id") == id, message + " id")
  require(number(value, "version") == 1, message + " version")
}

///|
fn request(version : Int, id : Int, op : String, fields : String) -> String {
  "{\"version\":" +
  version.to_string() +
  ",\"id\":" +
  id.to_string() +
  ",\"op\":\"" +
  op +
  "\"" +
  fields +
  "}"
}

///|
fn assert_state(
  value : Json,
  expected : Array[Int],
  message : String,
) -> Unit raise Error {
  let actual = state(value)
  require(actual.length() == expected.length(), message)
  for index, item in actual {
    require(state_number([item], 0) == expected[index], message)
  }
}

///|
async fn capture_png(
  directory : String,
  name : String,
  response : Json,
  capture_path : String,
) -> Json raise Error {
  let values = state(response)
  let width = state_number(values, 6)
  let height = state_number(values, 7)
  let rgba = @fs.read_file(capture_path).binary()
  require(rgba.length() == width * height * 4, name + " RGBA length")
  let image = @image.ImageData::{ width, height, data: rgba, }
  let encoded = @image.encode_png(image)
  @fs.write_file(directory + "/" + name + ".png", encoded)
  let x0 = state_number(values, 0)
  let y0 = state_number(values, 1)
  let rw = state_number(values, 2)
  let rh = state_number(values, 3)
  let active = state_number(values, 4) == 1
  let foreground = if active { [242, 97, 26, 255] } else { [20, 166, 173, 255] }
  let background = [5, 20, 38, 255]
  let mut offset = 0
  while offset < rgba.length() {
    let pixel = offset / 4
    let x = pixel % width
    let y = pixel / width
    let expected = if x >= x0 && x < x0 + rw && y >= y0 && y < y0 + rh {
      foreground
    } else {
      background
    }
    let mut channel = 0
    while channel < 4 {
      require(
        (rgba[offset + channel].to_int() - expected[channel]).abs() <= 1,
        name + " pixel",
      )
      channel = channel + 1
    }
    offset = offset + 4
  }
  Json::object({
    "name": Json::string(name),
    "width": Json::number(width.to_double()),
    "height": Json::number(height.to_double()),
    "bytes": Json::number(rgba.length().to_double()),
  })
}

///|
async fn verify_session(
  root : String,
  directory : String,
  capture_path : String,
  bridge : String,
) -> Array[Json] raise Error {
  let captures : Array[Json] = []
  let executable = root +
    "/_build/native/release/build/examples/p0/native_headless/native_headless.exe"
  let stderr = with_raw(executable, bridge, capture_path, async fn(session) {
    let initial = session.request(request(1, 1, "snapshot", ""))
    assert_meta(initial, 1, "snapshot")
    is_true(initial, "snapshot")
    require(number(initial, "frame") == 0, "initial frame")
    assert_state(initial, [260, 144, 120, 72, 0, 0, 640, 360], "initial state")
    let captured = session.request(
      request(1, 2, "capture", ",\"expected_revision\":0"),
    )
    assert_meta(captured, 2, "initial capture")
    is_true(captured, "initial capture")
    require(number(captured, "frame") == 1, "initial frame")
    captures.push(capture_png(directory, "initial", captured, capture_path))
    let moved = session.request(
      request(1, 3, "move", ",\"x\":10,\"y\":20,\"expected_revision\":0"),
    )
    assert_meta(moved, 3, "move")
    is_true(moved, "move")
    require(
      state_number(state(moved), 0) == 10 && state_number(state(moved), 1) == 20,
      "move position",
    )
    require(state_number(state(moved), 5) == 1, "move revision")
    let moved_capture = session.request(
      request(1, 4, "capture", ",\"expected_revision\":1"),
    )
    assert_meta(moved_capture, 4, "moved capture")
    is_true(moved_capture, "moved capture")
    require(number(moved_capture, "frame") == 2, "moved frame")
    captures.push(capture_png(directory, "moved", moved_capture, capture_path))
    let active = session.request(
      request(1, 5, "activate", ",\"expected_revision\":1"),
    )
    assert_meta(active, 5, "activate")
    is_true(active, "activate")
    let active_capture = session.request(
      request(1, 6, "capture", ",\"expected_revision\":2"),
    )
    assert_meta(active_capture, 6, "active capture")
    is_true(active_capture, "active capture")
    assert_state(
      active_capture,
      [10, 20, 120, 72, 1, 2, 640, 360],
      "active capture state",
    )
    require(
      state_number(state(active), 4) == 1 && state_number(state(active), 5) == 2,
      "active state",
    )
    require(number(active_capture, "frame") == 3, "active frame")
    captures.push(
      capture_png(directory, "active", active_capture, capture_path),
    )
    let resized = session.request(
      request(
        1, 7, "resize", ",\"width\":317,\"height\":193,\"expected_revision\":2",
      ),
    )
    assert_meta(resized, 7, "resize")
    is_true(resized, "resize")
    require(state_number(state(resized), 5) == 3, "resize revision")
    require(
      state_number(state(resized), 6) == 317 &&
      state_number(state(resized), 7) == 193,
      "resize dimensions",
    )
    let resized_capture = session.request(
      request(1, 8, "capture", ",\"expected_revision\":3"),
    )
    assert_meta(resized_capture, 8, "resized capture")
    is_true(resized_capture, "resized capture")
    assert_state(
      resized_capture,
      [10, 20, 120, 72, 1, 3, 317, 193],
      "resized capture state",
    )
    require(number(resized_capture, "frame") == 4, "resized frame")
    captures.push(
      capture_png(directory, "resized", resized_capture, capture_path),
    )
    let stable = state(resized_capture)
    let stale = session.request(
      request(1, 9, "move", ",\"x\":0,\"y\":0,\"expected_revision\":1"),
    )
    assert_meta(stale, 9, "stale")
    require(
      field(stale, "error") == Some(Json::string("stale_revision")),
      "stale error",
    )
    require(state(stale) == stable, "stale state")
    require(number(stale, "frame") == 4, "stale frame")
    let invalid_resize = session.request(
      request(1, 11, "resize", ",\"width\":0,\"height\":1"),
    )
    assert_meta(invalid_resize, 11, "invalid resize")
    require(
      field(invalid_resize, "ok") == Some(Json::boolean(false)),
      "invalid resize",
    )
    require(state(invalid_resize) == stable, "invalid resize state")
    let unknown = session.request(request(1, 12, "nope", ""))
    assert_meta(unknown, 12, "unknown")
    require(
      field(unknown, "ok") == Some(Json::boolean(false)),
      "unknown operation",
    )
    require(state(unknown) == stable, "unknown state")
    let unsupported = session.request(request(2, 13, "snapshot", ""))
    assert_meta(unsupported, 13, "unsupported version")
    require(
      field(unsupported, "error") == Some(Json::string("unsupported_version")),
      "unsupported version error",
    )
    require(state(unsupported) == stable, "unsupported version state")
    let malformed = session.request("{malformed")
    require(field(malformed, "ok") == Some(Json::boolean(false)), "malformed")
    require(state(malformed) == stable, "malformed state")
    require(number(malformed, "frame") == 4, "malformed frame")
    let oversized = session.request(String::from_array(Array::make(5000, 'x')))
    require(
      field(oversized, "error") == Some(Json::string("line_too_long")),
      "oversized",
    )
    require(state(oversized) == stable, "oversized state")
    require(number(oversized, "frame") == 4, "oversized frame")
    let recovered = session.request(request(1, 14, "snapshot", ""))
    assert_meta(recovered, 14, "recovery")
    is_true(recovered, "recovery")
    require(state(recovered) == stable, "recovery state")
    require(number(recovered, "frame") == 4, "recovery frame")
    let shutdown = session.request(request(1, 15, "shutdown", ""))
    assert_meta(shutdown, 15, "shutdown")
    is_true(shutdown, "shutdown")
    session.finish()
  })
  @fs.write_file(directory + "/stderr.log", @utf8.encode(stderr))
  require(stderr.to_lower().contains("dx12"), "DX12 diagnostic")
  captures
}

///|
async fn verify_failure_session(
  root : String,
  bridge : String,
  capture_path : String,
) -> Unit raise Error {
  let executable = root +
    "/_build/native/release/build/examples/p0/native_headless/native_headless.exe"
  let stderr = with_raw(executable, bridge, capture_path, async fn(session) {
    let initial = session.request(request(1, 1, "snapshot", ""))
    assert_meta(initial, 1, "failure snapshot")
    is_true(initial, "failure snapshot")
    let stable = state(initial)
    let captured = session.request(
      request(1, 2, "capture", ",\"expected_revision\":0"),
    )
    assert_meta(captured, 2, "failure capture")
    require(
      field(captured, "error") == Some(Json::string("capture_failed")),
      "capture failure",
    )
    require(number(captured, "frame") == 0, "capture failure frame")
    require(state(captured) == stable, "capture failure state")
    let shutdown = session.request(request(1, 3, "shutdown", ""))
    assert_meta(shutdown, 3, "failure shutdown")
    is_true(shutdown, "failure shutdown")
    session.finish()
  })
  ignore(stderr)
}

///|
async fn main {
  let root = @fs.realpath(".")
  let mode = if @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1") {
    "fallback"
  } else {
    "default"
  }
  let directory = root + "/.work/native-headless/" + mode
  if !@fs.exists(directory) {
    @fs.mkdir(directory, recursive=true)
  }
  let capture_path = directory + "/capture.rgba"
  let bridge = root + "/.work/native-cargo/release/metonic_wgpu_probe.dll"
  let captures : Ref[Array[Json]] = { val: [], }
  @async.with_timeout(20000, async fn() {
    captures.val = verify_session(root, directory, capture_path, bridge)
    verify_stdio(root, bridge, capture_path)
    verify_failure_session(
      root,
      root + "/.work/native-cargo/release/missing-probe.dll",
      capture_path,
    )
    verify_failure_session(root, bridge, "")
    let eof_stderr = with_raw(
      root +
      "/_build/native/release/build/examples/p0/native_headless/native_headless.exe",
      bridge,
      capture_path,
      async fn(session) { session.finish() },
    )
    ignore(eof_stderr)
    let results = Json::object({
      "mode": Json::string(mode),
      "ok": Json::boolean(true),
      "captures": Json::array(captures.val),
      "checks": Json::array([
        Json::string("state"),
        Json::string("captures"),
        Json::string("errors"),
        Json::string("EOF"),
        Json::string("gpu-failure"),
        Json::string("capture-path-failure"),
        Json::string("oversize"),
        Json::string("shutdown"),
        Json::string("stdio"),
      ]),
    })
    @fs.write_file(directory + "/results.json", results.stringify())
  }) catch {
    error => {
      println(@debug.to_string(error))
      abort("native headless verification failed: " + @debug.to_string(error))
    }
  }
}
