///|
test "input lifetime requires completed asynchronous assertions without page errors" {
  let success = "PASS production_input_owner both_fields composition selection stop restart pending_frames"
  verify_input_lifetime({ "text": Json::string(success), "errors": 0 }, "js")
  let observations : Array[Json] = [
    { "text": Json::string(success), "errors": 1 },
    { "text": Json::string(success), "errors": -1 },
    { "text": "FAIL production_input_owner: stale frame", "errors": 0 },
    { "text": "", "errors": 0 },
    {
      "text": "PASS production_input_owner both_fields composition selection stop restart",
      "errors": 0,
    },
    { "text": Json::string(success) },
  ]
  for observation in observations {
    let rejected = try {
      verify_input_lifetime(observation, "wasm-gc")
      false
    } catch {
      _ => true
    }
    assert_eq(rejected, true)
  }
}
