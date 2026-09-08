///|
async fn verify_shared_view(host : BrowserHost) -> Unit {
  let actual = command(host, { "op": "view-bounds" })
  guard actual is Json::Array(elements) && elements.length() == 4 else {
    fail("shared input and request bounds missing")
  }
  let editor = elements[0]
  let request = elements[1]
  require(
    int_field(editor, "width") == 640 && int_field(editor, "height") == 96,
    "shared editor dimensions",
  )
  require(
    int_field(request, "width") == 176 && int_field(request, "height") == 40,
    "shared request dimensions",
  )
  require(
    int_field(elements[2], "width") == 272 &&
    int_field(elements[3], "width") == 176,
    "shared task control dimensions",
  )
  for
    entry in [
      (editor, 8),
      (request, 144),
      (elements[2], 224),
      (elements[3], 272),
    ] {
    let (element, y) = entry
    near_coordinate(element, "x", 8.0)
    near_coordinate(element, "y", y.to_double())
    require(
      string_field(element, "opacity") == "0",
      "visible DOM duplicates GPU view",
    )
  }
  let image = decode_png(
    { "png": command(host, { "op": "image", "name": "shared-view" }) },
    "png",
  )
  require(
    image.width >= 184 && image.height >= 184,
    "shared view image dimensions",
  )
  let mut ink = 0
  for y in 148..<180 {
    for x in 16..<176 {
      let at = (y * image.width + x) * 4
      if image.data[at].to_int() < 128 &&
        image.data[at + 1].to_int() < 128 &&
        image.data[at + 2].to_int() < 128 {
        ink += 1
      }
    }
  }
  require(ink > 30, "GPU request label has no visible glyphs")
}

///|
fn near_coordinate(
  value : Json,
  key : String,
  expected : Double,
) -> Unit raise VerifyFailure {
  guard field(value, key) is Some(Json::Number(actual, ..)) else {
    fail("missing shared view coordinate")
  }
  // The screenshot helper aligns a fractional CSS origin to a device pixel.
  require(
    actual > expected - 1 && actual < expected + 1,
    "shared DOM adapter position",
  )
}
