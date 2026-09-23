///|
test "replacement keeps both text texture generations until old resources release" {
  assert_eq(text_layer_bytes(64, 20), 5120UL)
  assert_eq(replacement_footprint(12, 992256UL, 12, 992256UL), (24, 1984512UL))
  assert_eq(replacement_footprint(12, 992256UL, 0, 0UL), (12, 992256UL))
}
