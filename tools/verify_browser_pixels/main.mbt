///|
suberror VerifyFailure {
  Failure(String)
} derive(Debug)

///|
fn fail(message : String) -> Unit raise VerifyFailure {
  raise VerifyFailure::Failure(message)
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
fn bytes_field(value : Json, key : String) -> Bytes raise VerifyFailure {
  let encoded = string_field(value, key)
  @base64.decode(encoded) catch {
    _ => {
      fail("invalid base64 " + key)
      Bytes::from_array([])
    }
  }
}

///|
fn box_json(x : Int, y : Int, width : Int, height : Int) -> Json {
  Json::object({
    "x": Json::number(x.to_double()),
    "y": Json::number(y.to_double()),
    "width": Json::number(width.to_double()),
    "height": Json::number(height.to_double()),
  })
}

///|
fn box_fields(
  value : Json,
  key : String,
) -> (Int, Int, Int, Int) raise VerifyFailure {
  let object = match field(value, key) {
    Some(v) => v
    _ => {
      fail("missing " + key)
      Json::object({})
    }
  }
  (
    int_field(object, "x"),
    int_field(object, "y"),
    int_field(object, "width"),
    int_field(object, "height"),
  )
}

///|
fn decode_png(
  value : Json,
  key : String,
) -> @image.ImageData raise VerifyFailure {
  let raw = bytes_field(value, key)
  @image.decode_png(raw) catch {
    _ => {
      fail("invalid PNG")
      @image.ImageData::{
        width: 1,
        height: 1,
        data: Bytes::from_array([0, 0, 0, 0]),
      }
    }
  }
}

///|
fn colour_box(
  image : @image.ImageData,
  teal : Bool,
) -> (Int, Int, Int, Int) raise VerifyFailure {
  let mut min_x = image.width
  let mut min_y = image.height
  let mut max_x = -1
  let mut max_y = -1
  for index = 0; index < image.data.length(); index = index + 4 {
    let r = image.data[index].to_int()
    let g = image.data[index + 1].to_int()
    let b = image.data[index + 2].to_int()
    let a = image.data[index + 3].to_int()
    let match_colour = if teal {
      a > 180 && r < 80 && g > 100 && b > 100
    } else {
      a > 180 && r > 180 && g >= 50 && g <= 150 && b < 80
    }
    if match_colour {
      let pixel = index / 4
      let x = pixel % image.width
      let y = pixel / image.width
      min_x = if x < min_x { x } else { min_x }
      min_y = if y < min_y { y } else { min_y }
      max_x = if x > max_x { x } else { max_x }
      max_y = if y > max_y { y } else { max_y }
    }
  }
  require(max_x >= 0, "empty bbox")
  (min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
}

///|
fn near(a : Int, b : Int, tolerance : Int) -> Bool {
  (a - b).abs() <= tolerance
}

///|
fn scene(request : Json) -> Json raise VerifyFailure {
  let stage = string_field(request, "stage")
  require(
    stage == "initial" ||
    stage == "active" ||
    stage == "moved" ||
    stage == "resized" ||
    stage == "reset",
    "unknown stage",
  )
  let image = decode_png(request, "png")
  let teal = stage == "initial" || stage == "reset"
  let box = colour_box(image, teal)
  if stage == "initial" || stage == "active" || stage == "reset" {
    require(near(box.2, 120, 2) && near(box.3, 72, 2), "invalid bbox size")
  }
  if stage == "initial" || stage == "resized" {
    let width = int_field(request, "canvasWidth")
    let height = int_field(request, "canvasHeight")
    require(
      width > 0 &&
      width <= 100000 &&
      height > 0 &&
      height <= 100000 &&
      near(image.width, width, 1) &&
      near(image.height, height, 1),
      "canvas dimensions",
    )
    if stage == "resized" {
      require(
        box.0 >= 0 &&
        box.1 >= 0 &&
        box.0 + box.2 <= width &&
        box.1 + box.3 <= height,
        "resized bbox bounds",
      )
    }
  }
  if stage == "active" {
    let previous = box_fields(request, "previous")
    require(
      near(box.0, previous.0, 2) && near(box.1, previous.1, 2),
      "active position",
    )
  } else if stage == "moved" {
    let previous = box_fields(request, "previous")
    require(
      near(box.0, previous.0 + 10, 1) && near(box.1, previous.1, 1),
      "moved position",
    )
  }
  box_json(box.0, box.1, box.2, box.3)
}

///|
fn crop(request : Json) -> Json raise VerifyFailure {
  let image = decode_png(request, "png")
  let requested_width = int_field(request, "width")
  require(requested_width > 0 && requested_width <= 100000, "crop width")
  let width = if requested_width < 640 { requested_width } else { 640 }
  require(image.width >= width + 8 && image.height >= 104, "crop bounds")
  let pixels = Array::make(width * 96 * 4, b'\x00')
  for y in 0..<96 {
    for x in 0..<width {
      let source = ((y + 8) * image.width + x + 8) * 4
      let target = (y * width + x) * 4
      for channel in 0..<4 {
        pixels[target + channel] = image.data[source + channel]
      }
    }
  }
  Json::object({
    "width": Json::number(width.to_double()),
    "fullWidth": Json::number(image.width.to_double()),
    "data": Json::string(@base64.encode(Bytes::from_array(pixels))),
    "pixels": Json::number(pixels.length().to_double()),
  })
}

///|
fn text_initial(request : Json) -> Json raise VerifyFailure {
  let data = bytes_field(request, "data")
  let width = int_field(request, "width")
  require(
    width > 0 && width <= 640 && data.length() == width * 96 * 4,
    "text dimensions",
  )
  let mut dark = false
  let mut bright = false
  for index = 0; index < data.length(); index = index + 4 {
    dark = dark || data[index].to_int() < 32
    bright = bright || data[index].to_int() > 240
  }
  require(dark && bright, "text colors")
  Json::null()
}

///|
fn text_compare(request : Json) -> Json raise VerifyFailure {
  let actual = bytes_field(request, "actual")
  let expected = bytes_field(request, "expected")
  require(
    actual.length() > 0 &&
    actual.length() % 4 == 0 &&
    actual.length() <= 640 * 96 * 4 &&
    expected.length() > 0 &&
    expected.length() % 4 == 0 &&
    expected.length() <= 640 * 96 * 4,
    "text comparison dimensions",
  )
  let equal = match field(request, "equal") {
    Some(value) if value is Json::True => true
    Some(value) if value is Json::False => false
    _ => {
      fail("missing boolean equal")
      false
    }
  }
  require((actual == expected) == equal, "text comparison")
  Json::null()
}

///|
fn text_blank(request : Json) -> Json raise VerifyFailure {
  let data = bytes_field(request, "data")
  let width = int_field(request, "width")
  require(
    width > 0 && width <= 640 && data.length() == width * 96 * 4,
    "blank dimensions",
  )
  for index = 0; index < data.length(); index = index + 4 {
    require(
      data[index].to_int() >= 254 &&
      data[index + 1].to_int() >= 254 &&
      data[index + 2].to_int() >= 254 &&
      data[index + 3] == 255,
      "not blank",
    )
  }
  Json::null()
}

///|
fn dpr2(request : Json) -> Json raise VerifyFailure {
  let image = decode_png(request, "png")
  let reference = bytes_field(request, "reference")
  require(
    image.width >= 1296 &&
    image.height >= 720 &&
    reference.length() == 640 * 96 * 4,
    "DPR dimensions",
  )
  for y in 0..<192 {
    for x in 0..<1280 {
      let actual = ((y + 16) * image.width + x + 16) * 4
      let expected = (y / 2 * 640 + x / 2) * 4
      for channel in 0..<4 {
        require(
          image.data[actual + channel] == reference[expected + channel],
          "DPR pixels",
        )
      }
    }
  }
  Json::null()
}

///|
fn verify_checked(request : String) -> String raise Error {
  let value = @json.parse(request)
  let action = string_field(value, "action")
  let result = if action == "scene" {
    scene(value)
  } else if action == "crop" {
    crop(value)
  } else if action == "text_initial" {
    text_initial(value)
  } else if action == "text_compare" {
    text_compare(value)
  } else if action == "text_blank" {
    text_blank(value)
  } else if action == "dpr2" {
    dpr2(value)
  } else {
    fail("unknown action")
    Json::null()
  }
  Json::object({ "ok": Json::boolean(true), "value": result }).stringify()
}

///|
#export_name("verify")
pub fn verify(request : String) -> String {
  verify_checked(request) catch {
    error =>
      Json::object({
        "ok": Json::boolean(false),
        "error": Json::string(error.to_string()),
      }).stringify()
  }
}
