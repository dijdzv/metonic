///|
test "typed binding returns success and domain error" {
  let endpoint = binding()
  assert_eq(endpoint.call({ id: "1" }), Ok({ name: "月兎" }))
  assert_eq(endpoint.call({ id: "missing" }), Err(@api.NotFound))
}
