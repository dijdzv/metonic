///|
test "typed request envelope" {
  let procedure : @rpc.Procedure[String, String, String] = @rpc.Procedure::new(
    "echo.v1",
  )
  let request_json = request(procedure, "hello")
  match request_json {
    Json::Object(fields) => {
      assert_eq(fields.get("procedure"), Some(Json::string("echo.v1")))
      assert_eq(fields.get("input"), Some(Json::string("hello")))
    }
    _ => assert_eq(false, true)
  }
}

///|
test "unknown procedure is structured protocol error" {
  let procedure : @rpc.Procedure[String, String, String] = @rpc.Procedure::new(
    "echo.v1",
  )
  let binding = @rpc.bind(procedure, (_ : String) => Ok("ok"))
  let ep = endpoint(binding, (_ : String) => "error")
  let reply = dispatch(
    ep, "{\"version\":1,\"procedure\":\"other\",\"input\":\"x\"}",
  )
  assert_eq(reply.status, 404)
}

///|
test "protocol echo unicode roundtrip" {
  let p : @rpc.Procedure[String, String, String] = @rpc.Procedure::new(
    "echo.v1",
  )
  let binding = @rpc.bind(p, fn(input) { Ok(input) })
  let endpoint = endpoint(binding, fn(error) { error })
  let request_json = request(p, "月兎")
  let reply = dispatch(endpoint, request_json.stringify())
  let decoded = response(p, reply.status, reply.body, fn(code) { Some(code) })
  assert_eq(decoded, Ok("月兎"))
}

///|
test "protocol domain and remote errors" {
  let p : @rpc.Procedure[String, String, String] = @rpc.Procedure::new(
    "missing.v1",
  )
  let binding = @rpc.bind(p, fn(_input) { Err("missing") })
  let endpoint = endpoint(binding, fn(error) { error })
  let reply = dispatch(endpoint, request(p, "x").stringify())
  assert_eq(
    response(p, reply.status, reply.body, fn(code) { Some(code) }),
    Err(Domain("missing")),
  )
  assert_eq(
    response(p, reply.status, reply.body, fn(_code) { None }),
    Err(Remote("missing")),
  )
}

///|
test "protocol malformed and unknown procedure envelopes" {
  let p : @rpc.Procedure[String, String, String] = @rpc.Procedure::new(
    "echo.v1",
  )
  let binding = @rpc.bind(p, fn(input) { Ok(input) })
  let ep = endpoint(binding, fn(error) { error })
  let malformed = dispatch(ep, "{")
  assert_eq(
    @codec.parse(malformed.body.stringify()),
    @codec.parse(
      "{\"version\":1,\"ok\":false,\"error\":{\"kind\":\"protocol\",\"code\":\"invalid_json\"}}",
    ),
  )
  let unknown = dispatch(
    ep, "{\"version\":1,\"procedure\":\"unknown\",\"input\":\"x\"}",
  )
  assert_eq(
    @codec.parse(unknown.body.stringify()),
    @codec.parse(
      "{\"version\":1,\"ok\":false,\"error\":{\"kind\":\"protocol\",\"code\":\"unknown_procedure\"}}",
    ),
  )
}

///|
test "protocol response validation errors" {
  let p : @rpc.Procedure[String, String, String] = @rpc.Procedure::new(
    "echo.v1",
  )
  assert_eq(
    response(
      p,
      200,
      @codec.parse("{\"version\":2,\"ok\":true,\"output\":\"x\"}"),
      fn(_code) { None },
    ),
    Err(Protocol("invalid_response")),
  )
  assert_eq(
    response(p, 200, @codec.parse("{\"version\":1,\"ok\":true}"), fn(_code) {
      None
    }),
    Err(Protocol("invalid_response")),
  )
  assert_eq(
    response(p, 200, @codec.parse("{\"version\":1,\"ok\":true,\"output\":1}"), fn(
      _code,
    ) {
      None
    }),
    Err(Protocol("invalid_response")),
  )
  assert_eq(
    response(
      p,
      500,
      @codec.parse(
        "{\"version\":1,\"ok\":false,\"error\":{\"kind\":\"domain\",\"code\":\"missing\"}}",
      ),
      fn(_code) { None },
    ),
    Err(Protocol("invalid_response")),
  )
}

///|
test "protocol int64 uint64 decimal roundtrip" {
  let signed : Int64 = 9007199254740993L
  let unsigned : UInt64 = 18446744073709551615UL
  assert_eq(@codec.to_json(signed), Json::string("9007199254740993"))
  assert_eq(@codec.to_json(unsigned), Json::string("18446744073709551615"))
  assert_eq(@codec.from_json(@codec.to_json(signed)), signed)
  assert_eq(@codec.from_json(@codec.to_json(unsigned)), unsigned)
}

///|
test "invalid input does not call handler" {
  let calls = Ref(0)
  let p : @rpc.Procedure[String, String, String] = @rpc.Procedure::new(
    "echo.v1",
  )
  let binding = @rpc.bind(p, fn(input) {
    calls.val += 1
    Ok(input)
  })
  let ep = endpoint(binding, fn(error) { error })
  let invalid = dispatch(
    ep, "{\"version\":1,\"procedure\":\"echo.v1\",\"input\":1}",
  )
  assert_eq(invalid.status, 400)
  assert_eq(calls.val, 0)
  let valid = dispatch(ep, request(p, "ok").stringify())
  assert_eq(valid.status, 200)
  assert_eq(calls.val, 1)
}

///|
test "request body byte boundaries" {
  let calls = Ref(0)
  let p : @rpc.Procedure[String, String, String] = @rpc.Procedure::new(
    "echo.v1",
  )
  let binding = @rpc.bind(p, fn(input) {
    calls.val += 1
    Ok(input)
  })
  let ep = endpoint(binding, fn(error) { error })
  let prefix = request(p, "x").stringify()
  let valid = dispatch(
    ep,
    prefix + String::from_array(Array::make(65536 - prefix.length(), ' ')),
  )
  assert_eq(valid.status, 200)
  assert_eq(calls.val, 1)
  let oversized = dispatch(
    ep,
    prefix + String::from_array(Array::make(65537 - prefix.length(), ' ')),
  )
  assert_eq(oversized.status, 413)
  assert_eq(
    @codec.parse(oversized.body.stringify()),
    @codec.parse(
      "{\"version\":1,\"ok\":false,\"error\":{\"kind\":\"protocol\",\"code\":\"request_too_large\"}}",
    ),
  )
  assert_eq(calls.val, 1)
}

///|
test "deep malformed json does not call handler" {
  let calls = Ref(0)
  let p : @rpc.Procedure[String, String, String] = @rpc.Procedure::new(
    "echo.v1",
  )
  let binding = @rpc.bind(p, fn(input) {
    calls.val += 1
    Ok(input)
  })
  let ep = endpoint(binding, fn(error) { error })
  let nested = String::from_array(Array::make(33, '[')) +
    "0" +
    String::from_array(Array::make(33, ']'))
  let result = dispatch(ep, nested)
  assert_eq(result.status, 400)
  assert_eq(calls.val, 0)
}
