///|
suberror TestFailure {
  TestFailure(String)
}

///|
fn expect_failure(
  f : () -> Unit raise Error,
  expected : String,
) -> Unit raise Error {
  let mut message : String? = None
  f() catch {
    error => message = Some(@debug.to_string(error))
  }
  match message {
    Some(value) => if !value.contains(expected) { raise TestFailure(value) }
    None => raise TestFailure("expected failure containing " + expected)
  }
}

///|
extern "js" fn fake_client() -> Client =
  #| () => ({
  #|   listTools: async () => ({ tools: [] }),
  #|   callTool: async () => { throw new Error("must not call"); },
  #| })

///|
fn text_result(text : String) -> Json {
  Json::object({
    "content": Json::array([
      Json::object({ "type": Json::string("text"), "text": Json::string(text) }),
    ]),
  })
}

///|
fn pixel_response(width : Int, height : Int) -> Json {
  Json::object({
    "state": Json::array([
      Json::number(0.0),
      Json::number(0.0),
      Json::number(1.0),
      Json::number(1.0),
      Json::number(1.0),
      Json::number(2.0),
      Json::number(width.to_double()),
      Json::number(height.to_double()),
    ]),
  })
}

///|
fn png64(width : Int, height : Int, data : Array[Byte]) -> String raise Error {
  @base64.encode(
    @image.encode_png(@image.ImageData::{
      width,
      height,
      data: Bytes::from_array(data),
    }),
  )
}

///|
test "MCP response text requires one valid text content" {
  expect_failure(
    fn() raise Error {
      ignore(response_text(Json::object({ "content": Json::array([]) })))
    },
    "response text",
  )
  expect_failure(
    fn() raise Error { ignore(response_text(text_result("{invalid-json"))) },
    "JSON",
  )
}

///|
test "MCP pixel checker accepts the active 1x1 pixel" {
  let encoded = png64(1, 1, [b'\xf2', b'a', b'\x1a', b'\xff'])
  ignore(check_pixels(pixel_response(1, 1), encoded))
}

///|
test "MCP pixel checker rejects wrong pixels and dimensions" {
  let wrong = png64(1, 1, [b'\x05', b'\x14', b'\x26', b'\xff'])
  expect_failure(
    fn() raise Error { ignore(check_pixels(pixel_response(1, 1), wrong)) },
    "pixel",
  )
  let two_pixels = png64(2, 1, [
    b'\xf2', b'a', b'\x1a', b'\xff', b'\x05', b'\x14', b'\x26', b'\xff',
  ])
  expect_failure(
    fn() raise Error { ignore(check_pixels(pixel_response(1, 1), two_pixels)) },
    "dimension",
  )
}

///|
test "MCP pixel checker rejects oversized dimensions before PNG decode" {
  let header = @base64.encode(
    Bytes::from_array([
      b'\x89', b'P', b'N', b'G', b'\x0d', b'\x0a', b'\x1a', b'\x0a', b'\x00', b'\x00',
      b'\x00', b'\x0d', b'I', b'H', b'D', b'R', b'\x00', b'\x00', b'\x08', b'\x01',
      b'\x00', b'\x00', b'\x00', b'\x01',
    ]),
  )
  expect_failure(
    fn() raise Error { ignore(check_pixels(pixel_response(1, 1), header)) },
    "dimension",
  )
}

///|
async test "MCP verifier rejects a client with missing tools" {
  let mut message : String? = None
  try {
    @moonbitlang/async.with_timeout(2000, async fn() {
      ignore(verify(fake_client()).wait())
    })
    ()
  } catch {
    error => message = Some(error.to_string())
  }
  match message {
    Some(value) => assert_true(value.contains("tool names length"))
    None => assert_true(false)
  }
}
