///|
suberror VerifyFailure {
  VerifyFailure(String)
}

///|
fn fail(message : String) -> Unit raise Error {
  println(message)
  raise VerifyFailure(message)
}

///|
fn require(value : Bool, message : String) -> Unit raise Error {
  if !value {
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
    Some(Json::Number(value, ..)) if value.to_int().to_double() == value =>
      value.to_int()
    _ => {
      fail("missing integer field " + key)
      0
    }
  }
}

///|
fn state_field(object : Json) -> Array[Json] raise Error {
  match field(object, "state") {
    Some(Json::Array(values)) if values.length() == 8 => values
    _ => {
      fail("missing state")
      []
    }
  }
}

///|
fn state_int(values : Array[Json], index : Int) -> Int raise Error {
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
fn parse_line(line : Bytes) -> Json raise Error {
  @json.parse(@utf8.decode(line)) catch {
    _ => {
      fail("stdout contained a non-JSON line")
      Json::object({})
    }
  }
}

///|
fn response_error(response : Json, message : String) -> Unit raise Error {
  require(!bool_field(response, "ok"), message)
  match field(response, "error") {
    Some(Json::String(_)) => ()
    _ => fail(message + " missing error")
  }
}

///|
fn response_error_text(
  response : Json,
  message : String,
  expected : String,
) -> Unit raise Error {
  response_error(response, message)
  require(field(response, "error") == Some(Json::string(expected)), message)
}

///|
fn response_error_contains(
  response : Json,
  message : String,
  expected : String,
) -> Unit raise Error {
  response_error(response, message)
  match field(response, "error") {
    Some(Json::String(value)) => require(value.contains(expected), message)
    _ => fail(message + " missing error")
  }
}

///|
fn pixel_check(response : Json, encoded : String) -> Bytes raise Error {
  let values = state_field(response)
  let width = state_int(values, 6)
  let height = state_int(values, 7)
  let png = @base64.decode(encoded)
  let image = @image.decode_png(png)
  require(image.width == width && image.height == height, "PNG dimensions")
  require(image.data.length() == width * height * 4, "PNG length")
  let x0 = state_int(values, 0)
  let y0 = state_int(values, 1)
  let rw = state_int(values, 2)
  let rh = state_int(values, 3)
  let expected_foreground = [242, 97, 26, 255]
  let expected_background = [5, 20, 38, 255]
  let mut offset = 0
  while offset < image.data.length() {
    let pixel = offset / 4
    let x = pixel % width
    let y = pixel / width
    let expected = if x >= x0 && x < x0 + rw && y >= y0 && y < y0 + rh {
      expected_foreground
    } else {
      expected_background
    }
    for channel in 0..<4 {
      require(
        (image.data[offset + channel].to_int() - expected[channel]).abs() <= 1,
        "PNG pixel mismatch",
      )
    }
    offset += 4
  }
  png
}

///|
async fn run_case_inner(
  root : String,
  requests : Array[Bytes],
  terminate_each : Bool,
  expected_responses : Int,
) -> Array[Json] raise Error {
  let artifact = root +
    "/_build/wasm/release/build/tools/native_cli/native_cli.wasm"
  let moonrun = root + "/.tools/moonbit/bin/moonrun.exe"
  let responses : Array[Json] = []
  @async.with_task_group() <| group => {
    let (reader, stdout) = @process.read_from_process()
    let (stdin, writer) = @process.write_to_process()
    let process = @process.spawn(
      group,
      moonrun,
      [artifact, "--root", root],
      stdin~,
      stdout~,
      no_console_window=true,
      no_wait=true,
      cancel_handler=@process.hard_cancel(),
    )
    group.add_defer(fn() {
      writer.close()
      reader.close()
      process.cancel()
    })
    group.spawn_bg() <| () => {
      defer writer.close()
      for index, request in requests {
        writer.write(request)
        if terminate_each || index + 1 < requests.length() {
          writer.write("\n")
        }
      }
    }
    let mut pending : Array[Byte] = []
    let mut stdout_closed = false
    while !stdout_closed {
      match reader.read_some(max_len=4096) {
        None => stdout_closed = true
        Some(chunk) =>
          for byte in chunk.iter() {
            if byte == b'\n' {
              responses.push(parse_line(Bytes::from_array(pending)))
              pending = []
            } else {
              pending.push(byte)
            }
          }
      }
    }
    require(
      responses.length() == expected_responses,
      "native CLI response count " +
      responses.length().to_string() +
      "/" +
      expected_responses.to_string(),
    )
    require(pending.length() == 0, "native CLI emitted unterminated output")
    require(process.wait() == 0, "native CLI exit status")
  }
  responses
}

///|
async fn run_case(
  root : String,
  requests : Array[Bytes],
  terminate_each : Bool,
  expected_responses : Int,
) -> Array[Json] raise Error {
  @async.with_timeout(20000, async fn() {
    run_case_inner(root, requests, terminate_each, expected_responses)
  })
}

///|
fn make_request(op : String, args : Json) -> String {
  Json::object({ "op": Json::string(op), "args": args }).stringify()
}

///|
async fn check_scenario_one(
  root : String,
  mode : String,
) -> Array[String] raise Error {
  let requests = [
    @utf8.encode(make_request("snapshot", Json::object({}))),
    @utf8.encode(
      make_request(
        "move",
        Json::object({
          "x": Json::number(10.0),
          "y": Json::number(20.0),
          "expected_revision": Json::number(0.0),
        }),
      ),
    ),
    @utf8.encode(
      make_request(
        "activate",
        Json::object({ "expected_revision": Json::number(1.0) }),
      ),
    ),
    @utf8.encode(
      make_request(
        "capture",
        Json::object({ "expected_revision": Json::number(2.0) }),
      ),
    ),
    @utf8.encode(
      make_request(
        "move",
        Json::object({
          "x": Json::number(0.0),
          "y": Json::number(0.0),
          "expected_revision": Json::number(0.0),
        }),
      ),
    ),
    Bytes::from_array([b'{']),
    @utf8.encode(make_request("snapshot", Json::object({}))),
  ]
  let responses = run_case(root, requests, true, 7)
  let initial = responses[0]
  require(bool_field(initial, "ok"), "scenario1 snapshot")
  let initial_state = state_field(initial)
  require(
    state_int(initial_state, 0) == 260 &&
    state_int(initial_state, 1) == 144 &&
    state_int(initial_state, 2) == 120 &&
    state_int(initial_state, 3) == 72 &&
    state_int(initial_state, 4) == 0 &&
    state_int(initial_state, 5) == 0 &&
    state_int(initial_state, 6) == 640 &&
    state_int(initial_state, 7) == 360,
    "scenario1 initial state",
  )
  let moved = responses[1]
  require(bool_field(moved, "ok"), "scenario1 move")
  let moved_state = state_field(moved)
  require(
    state_int(moved_state, 0) == 10 && state_int(moved_state, 1) == 20,
    "scenario1 position",
  )
  require(state_int(moved_state, 5) == 1, "scenario1 move revision")
  require(int_field(moved, "frame") == 0, "scenario1 move frame")
  let active = responses[2]
  require(bool_field(active, "ok"), "scenario1 activate")
  require(state_int(state_field(active), 4) == 1, "scenario1 active")
  require(state_int(state_field(active), 5) == 2, "scenario1 activate revision")
  let captured = responses[3]
  let captured_response = match field(captured, "response") {
    Some(value) => value
    None => {
      fail("scenario1 capture response")
      Json::object({})
    }
  }
  require(bool_field(captured_response, "ok"), "scenario1 capture")
  require(int_field(captured_response, "frame") == 1, "scenario1 frame")
  let captured_state = state_field(captured_response)
  require(
    state_int(captured_state, 0) == 10 &&
    state_int(captured_state, 1) == 20 &&
    state_int(captured_state, 2) == 120 &&
    state_int(captured_state, 3) == 72 &&
    state_int(captured_state, 4) == 1 &&
    state_int(captured_state, 5) == 2 &&
    state_int(captured_state, 6) == 640 &&
    state_int(captured_state, 7) == 360,
    "scenario1 capture dimensions",
  )
  let image_object : Map[String, Json] = match field(captured, "image") {
    Some(Json::Object(values)) => values
    _ => {
      fail("scenario1 image")
      Map([])
    }
  }
  require(
    image_object.get("mimeType") == Some(Json::string("image/png")),
    "scenario1 image mime",
  )
  let image = match field(captured, "image") {
    Some(Json::Object(values)) =>
      match values.get("data") {
        Some(Json::String(value)) => value
        _ => {
          fail("scenario1 image data")
          ""
        }
      }
    _ => {
      fail("scenario1 image")
      ""
    }
  }
  let png = pixel_check(captured_response, image)
  @fs.write_file(root + "/.work/native-cli/" + mode + ".png", png)
  response_error(responses[4], "scenario1 stale move")
  require(
    field(responses[4], "error") == Some(Json::string("stale_revision")),
    "scenario1 stale error",
  )
  require(state_field(responses[4]) == captured_state, "scenario1 stale state")
  response_error(responses[5], "scenario1 malformed JSON")
  require(bool_field(responses[6], "ok"), "scenario1 recovery snapshot")
  require(
    state_field(responses[6]) == captured_state,
    "scenario1 recovery state",
  )
  ["scenario1", "png", "stale", "malformed", "recovery"]
}

///|
async fn check_scenario_two(root : String) -> Unit raise Error {
  let oversized = String::from_array(Array::make(5000, 'x'))
  let requests = [
    @utf8.encode(oversized),
    @utf8.encode(make_request("snapshot", Json::object({}))),
  ]
  let responses = run_case(root, requests, true, 2)
  response_error(responses[0], "scenario2 oversized input")
  require(bool_field(responses[1], "ok"), "scenario2 recovery")
}

///|
async fn check_scenario_three(root : String) -> Unit raise Error {
  let responses = run_case(
    root,
    [@utf8.encode(make_request("snapshot", Json::object({})))],
    false,
    1,
  )
  require(bool_field(responses[0], "ok"), "scenario3 EOF snapshot")
}

///|
async fn check_input_contracts(root : String) -> Unit raise Error {
  let invalid_utf8 = run_case(
    root,
    [
      Bytes::from_array([b'\xff']),
      @utf8.encode(make_request("snapshot", Json::object({}))),
    ],
    true,
    2,
  )
  response_error_text(invalid_utf8[0], "invalid UTF-8", "invalid UTF-8 input")
  require(bool_field(invalid_utf8[1], "ok"), "invalid UTF-8 recovery")

  let null_args = run_case(
    root,
    [
      @utf8.encode("{\"op\":\"snapshot\",\"args\":null}"),
      @utf8.encode(make_request("snapshot", Json::object({}))),
    ],
    true,
    2,
  )
  response_error_contains(null_args[0], "null args", "args must be an object")
  require(bool_field(null_args[1], "ok"), "null args recovery")

  for expected in ["-1", "1.5", "2147483648"] {
    let request = "{\"op\":\"capture\",\"args\":{\"expected_revision\":" +
      expected +
      "}}"
    let responses = run_case(
      root,
      [
        @utf8.encode(request),
        @utf8.encode(make_request("snapshot", Json::object({}))),
      ],
      true,
      2,
    )
    response_error_contains(
      responses[0],
      "invalid expected_revision",
      "expected_revision",
    )
    require(bool_field(responses[1], "ok"), "expected_revision recovery")
  }

  let base = make_request("snapshot", Json::object({}))
  let base_length = @utf8.encode(base).length()
  let valid_4095 = base +
    String::from_array(Array::make(4095 - base_length, ' '))
  let valid_4096 = base +
    String::from_array(Array::make(4096 - base_length, ' '))
  let boundary = run_case(
    root,
    [
      @utf8.encode(valid_4095),
      @utf8.encode(valid_4096),
      @utf8.encode(make_request("snapshot", Json::object({}))),
    ],
    true,
    3,
  )
  require(bool_field(boundary[0], "ok"), "4095 byte request")
  response_error(boundary[1], "4096 byte request")
  require(bool_field(boundary[2], "ok"), "4096 byte recovery")
}

///|
async fn main {
  let root = @fs.realpath(".")
  let mode = if @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1") {
    "fallback"
  } else {
    "default"
  }
  let result_dir = root + "/.work/native-cli"
  if !@fs.exists(result_dir) {
    @fs.mkdir(result_dir, recursive=true)
  }
  @async.with_timeout(20000, async fn() {
    ignore(check_scenario_one(root, mode))
    check_scenario_two(root)
    check_scenario_three(root)
    check_input_contracts(root)
    check_lifecycle(root)
    @fs.write_file(
      result_dir + "/" + mode + ".json",
      Json::object({
        "mode": Json::string(mode),
        "ok": Json::boolean(true),
        "checks": Json::array(
          [
            "scenario1", "png", "stale", "malformed", "recovery", "oversize", "unterminated_eof",
            "invalid_utf8", "null_args", "invalid_revision", "request_4095", "request_4096",
            "lifecycle_eof_cleanup", "lifecycle_cancel_cleanup",
          ].map(fn(value) { Json::string(value) }),
        ),
      }).stringify(),
    )
  }) catch {
    error => abort("native CLI verification failed: " + error.to_string())
  }
}
