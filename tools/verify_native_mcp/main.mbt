///|
#external
pub type Client

///|
extern "js" fn list_tools(client : Client) -> @js_async.Promise[String] =
  #| async (client) => JSON.stringify(await client.listTools())

///|
extern "js" fn call_tool(
  client : Client,
  request : String,
) -> @js_async.Promise[String] =
  #| async (client, request) => JSON.stringify(await client.callTool(JSON.parse(request)))

///|

///|
pub suberror VerifyFailure {
  Failure(String)
} derive(Debug)

///|
pub impl Show for VerifyFailure with fn output(self, logger) {
  let Failure(message) = self
  logger.write_string(message)
}

///|
fn fail(message : String) -> Unit raise VerifyFailure {
  raise Failure(message)
}

///|
fn require(value : Bool, message : String) -> Unit raise VerifyFailure {
  if !value {
    fail(message)
  }
}

///|
fn field(value : Json, key : String) -> Json? {
  match value {
    Json::Object(values) => values.get(key)
    _ => None
  }
}

///|
fn bool_field(value : Json, key : String) -> Bool raise VerifyFailure {
  match field(value, key) {
    Some(Json::True) => true
    Some(Json::False) => false
    _ => {
      fail("missing boolean " + key)
      false
    }
  }
}

///|
fn string_field(value : Json, key : String) -> String raise VerifyFailure {
  match field(value, key) {
    Some(Json::String(value)) => value
    _ => {
      fail("missing string " + key)
      ""
    }
  }
}

///|
fn int_field(value : Json, key : String) -> Int raise VerifyFailure {
  match field(value, key) {
    Some(Json::Number(n, ..)) if n.to_int().to_double() == n => n.to_int()
    _ => {
      fail("missing integer " + key)
      0
    }
  }
}

///|
fn array_field(value : Json, key : String) -> Array[Json] raise VerifyFailure {
  match field(value, key) {
    Some(Json::Array(a)) => a
    _ => {
      fail("missing array " + key)
      []
    }
  }
}

///|
fn state(value : Json) -> Array[Json] raise VerifyFailure {
  let result = array_field(value, "state")
  require(result.length() == 8, "state length")
  result
}

///|
fn state_ints(value : Json) -> Array[Int] raise VerifyFailure {
  let source = state(value)
  let result : Array[Int] = []
  for index = 0; index < source.length(); index = index + 1 {
    match source[index] {
      Json::Number(n, ..) if n.to_int().to_double() == n =>
        result.push(n.to_int())
      _ => {
        fail("state integer")
        return []
      }
    }
  }
  result
}

///|
fn same_ints(left : Array[Int], right : Array[Int]) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index = 0; index < left.length(); index = index + 1 {
    if left[index] != right[index] {
      return false
    }
  }
  true
}

///|
fn contains_string(values : Array[String], wanted : String) -> Bool {
  for value in values {
    if value == wanted {
      return true
    }
  }
  false
}

///|
fn response_text(value : Json) -> Json raise VerifyFailure {
  match field(value, "content") {
    Some(Json::Array(items)) => {
      for item in items {
        match item {
          Json::Object(values) => {
            let kind = match values.get("type") {
              Some(Json::String(value)) => value
              _ => ""
            }
            match values.get("text") {
              Some(Json::String(text)) if kind == "text" =>
                return @json.parse(text) catch {
                  _ => {
                    fail("invalid native response JSON")
                    Json::object({})
                  }
                }
              _ => ()
            }
          }
          _ => ()
        }
      }
      fail("missing tool response text")
      Json::object({})
    }
    _ => {
      fail("missing tool content")
      Json::object({})
    }
  }
}

///|
async fn call(
  client : Client,
  name : String,
  args : Json,
) -> Json raise VerifyFailure {
  let request = Json::object({ "name": Json::string(name), "arguments": args }).stringify()
  let raw = @js_async.Promise::wait(call_tool(client, request)) catch {
    err => {
      fail("MCP call failed: " + @debug.to_string(err))
      ""
    }
  }
  @json.parse(raw) catch {
    _ => {
      fail("invalid MCP result JSON")
      Json::object({})
    }
  }
}

///|
fn image_data(value : Json) -> String raise VerifyFailure {
  match field(value, "content") {
    Some(Json::Array(items)) => {
      for item in items {
        match item {
          Json::Object(values) => {
            let kind = match values.get("type") {
              Some(Json::String(value)) => value
              _ => ""
            }
            let mime = match values.get("mimeType") {
              Some(Json::String(value)) => value
              _ => ""
            }
            match values.get("data") {
              Some(Json::String(data)) if kind == "image" &&
                mime == "image/png" &&
                data.length() > 0 => return data
              _ => ()
            }
          }
          _ => ()
        }
      }
      fail("missing capture image")
      ""
    }
    _ => {
      fail("missing capture content")
      ""
    }
  }
}

///|
fn check_pixels(response : Json, png64 : String) -> Unit raise VerifyFailure {
  let values = state_ints(response)
  let width = values[6]
  let height = values[7]
  require(
    width >= 1 && width <= 2048 && height >= 1 && height <= 2048,
    "invalid dimensions",
  )
  require(png64.length() <= 32 * 1024 * 1024, "PNG base64 too large")
  let raw = @base64.decode(png64) catch {
    _ => {
      fail("invalid PNG")
      Bytes::from_array([])
    }
  }
  require(raw.length() >= 24, "PNG header too short")
  require(
    raw[0] == 137 &&
    raw[1] == 80 &&
    raw[2] == 78 &&
    raw[3] == 71 &&
    raw[4] == 13 &&
    raw[5] == 10 &&
    raw[6] == 26 &&
    raw[7] == 10,
    "PNG signature",
  )
  require(
    raw[8] == 0 && raw[9] == 0 && raw[10] == 0 && raw[11] == 13,
    "PNG IHDR length",
  )
  require(
    raw[12] == 73 && raw[13] == 72 && raw[14] == 68 && raw[15] == 82,
    "PNG IHDR tag",
  )
  let png_width = (raw[16].to_int() << 24) |
    (raw[17].to_int() << 16) |
    (raw[18].to_int() << 8) |
    raw[19].to_int()
  let png_height = (raw[20].to_int() << 24) |
    (raw[21].to_int() << 16) |
    (raw[22].to_int() << 8) |
    raw[23].to_int()
  require(
    png_width >= 1 && png_width <= 2048 && png_height >= 1 && png_height <= 2048,
    "PNG header dimensions",
  )
  require(
    png_width == width && png_height == height,
    "PNG header dimensions mismatch",
  )
  let image = @image.decode_png(raw) catch {
    _ => {
      fail("invalid PNG")
      @image.ImageData::{
        width: 1,
        height: 1,
        data: Bytes::from_array([0, 0, 0, 0]),
      }
    }
  }
  require(image.width == width && image.height == height, "PNG dimensions")
  require(image.data.length() == width * height * 4, "PNG data length")
  let x0 = values[0]
  let y0 = values[1]
  let rw = values[2]
  let rh = values[3]
  for index = 0; index < image.data.length(); index = index + 4 {
    let pixel = index / 4
    let x = pixel % width
    let y = pixel / width
    let fg = x >= x0 && x < x0 + rw && y >= y0 && y < y0 + rh
    let expected = if fg { [242, 97, 26, 255] } else { [5, 20, 38, 255] }
    for channel = 0; channel < 4; channel = channel + 1 {
      require(
        (image.data[index + channel].to_int() - expected[channel]).abs() <= 1,
        "PNG pixel mismatch",
      )
    }
  }
}

///|
async fn verify_checked(client : Client) -> String raise VerifyFailure {
  let tools_raw = @js_async.Promise::wait(list_tools(client)) catch {
    err => {
      fail("listTools failed: " + @debug.to_string(err))
      ""
    }
  }
  let tools = @json.parse(tools_raw) catch {
    _ => {
      fail("invalid listTools JSON")
      Json::object({})
    }
  }
  let names : Array[String] = []
  match field(tools, "tools") {
    Some(Json::Array(items)) =>
      for item in items {
        match field(item, "name") {
          Some(Json::String(name)) => names.push(name)
          _ => fail("tool missing name")
        }
      }
    _ => fail("missing tool list")
  }
  let expected_names = [
    "native_activate", "native_capture", "native_move", "native_resize", "native_snapshot",
  ]
  require(names.length() == expected_names.length(), "tool names length")
  for name in expected_names {
    require(contains_string(names, name), "tool names")
  }

  let initial_outer = call(client, "native_snapshot", Json::object({}))
  let initial = response_text(initial_outer)
  let session_id = string_field(initial, "session_id")
  require(session_id.length() > 0, "empty session_id")
  let initial_state = state_ints(initial)
  require(
    same_ints(initial_state, [260, 144, 120, 72, 0, 0, 640, 360]),
    "initial state",
  )
  let moved = response_text(
    call(
      client,
      "native_move",
      Json::object({
        "x": Json::number(10.0),
        "y": Json::number(20.0),
        "expected_revision": Json::number(0.0),
      }),
    ),
  )
  require(string_field(moved, "session_id") == session_id, "move session_id")
  require(
    same_ints(state_ints(moved), [10, 20, 120, 72, 0, 1, 640, 360]),
    "move state",
  )
  let active = response_text(
    call(
      client,
      "native_activate",
      Json::object({ "expected_revision": Json::number(1.0) }),
    ),
  )
  require(
    string_field(active, "session_id") == session_id,
    "activate session_id",
  )
  require(
    state_ints(active) == [10, 20, 120, 72, 1, 2, 640, 360],
    "activate state",
  )
  let captured_outer = call(
    client,
    "native_capture",
    Json::object({ "expected_revision": Json::number(2.0) }),
  )
  require(!bool_field(captured_outer, "isError"), "capture isError")
  let captured = response_text(captured_outer)
  require(
    string_field(captured, "session_id") == session_id,
    "capture session_id",
  )
  require(
    same_ints(state_ints(captured), [10, 20, 120, 72, 1, 2, 640, 360]),
    "capture state",
  )
  require(int_field(captured, "frame") == 1, "capture frame")
  check_pixels(captured, image_data(captured_outer))

  let stale_outer = call(
    client,
    "native_move",
    Json::object({
      "x": Json::number(1.0),
      "y": Json::number(1.0),
      "expected_revision": Json::number(0.0),
    }),
  )
  let stale = response_text(stale_outer)
  require(bool_field(stale_outer, "isError"), "stale isError")
  require(
    field(stale, "error") == Some(Json::string("stale_revision")),
    "stale revision",
  )
  let invalid_outer = call(
    client,
    "native_resize",
    Json::object({
      "width": Json::number(0.0),
      "height": Json::number(0.0),
      "expected_revision": Json::number(2.0),
    }),
  )
  require(bool_field(invalid_outer, "isError"), "invalid resize isError")
  let after_invalid = response_text(
    call(client, "native_snapshot", Json::object({})),
  )
  require(
    string_field(after_invalid, "session_id") == session_id,
    "after invalid session_id",
  )
  require(
    same_ints(state_ints(after_invalid), state_ints(captured)),
    "invalid resize mutated state",
  )
  Json::object({
    "session_id": Json::string(session_id),
    "state": Json::array(state(captured)),
    "image_base64": Json::string(image_data(captured_outer)),
  }).stringify()
}

///|
#export_name("verify")
pub fn verify(client : Client) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() { verify_checked(client) })
}
