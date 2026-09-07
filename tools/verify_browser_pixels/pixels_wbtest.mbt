///|
fn png_fixture(
  teal : Bool,
  x : Int,
  width : Int,
  height : Int,
) -> String raise Error {
  let data : Array[Byte] = Array::make(width * height * 4, b'\x00')
  for y in 0..<height {
    for xx in 0..<width {
      let active = xx >= x && xx < x + 120 && y < 72
      let colour = if active && teal {
        [b'\x00', b'\xc8', b'\xc8', b'\xff']
      } else if active {
        [b'\xdc', b'\x64', b'\x14', b'\xff']
      } else {
        [b'\xff', b'\xff', b'\xff', b'\xff']
      }
      let i = (y * width + xx) * 4
      for channel in 0..<4 {
        data[i + channel] = colour[channel]
      }
    }
  }
  @base64.encode(
    @image.encode_png(@image.ImageData::{
      width,
      height,
      data: Bytes::from_array(data),
    }),
  )
}

///|
fn response_ok(raw : String) -> Bool raise Error {
  match @json.parse(raw) {
    Json::Object(values) => values.get("ok") == Some(Json::boolean(true))
    _ => false
  }
}

///|
fn solid_png(width : Int, height : Int, value : Byte) -> String raise Error {
  @base64.encode(
    @image.encode_png(@image.ImageData::{
      width,
      height,
      data: Bytes::make(width * height * 4, value),
    }),
  )
}

///|
test "pixel verifier accepts scene and rejects invalid inputs" {
  let initial = verify(
    Json::object({
      "action": Json::string("scene"),
      "stage": Json::string("initial"),
      "png": Json::string(png_fixture(true, 40, 200, 100)),
      "canvasWidth": Json::number(200.0),
      "canvasHeight": Json::number(100.0),
    }).stringify(),
  )
  assert_true(response_ok(initial))
  let bad = verify("not json")
  assert_true(!response_ok(bad))
}

///|
test "pixel verifier text compare and blank contracts" {
  let bytes = Bytes::make(640 * 96 * 4, b'\xff')
  let request = Json::object({
    "action": Json::string("text_blank"),
    "data": Json::string(@base64.encode(bytes)),
    "width": Json::number(640.0),
  }).stringify()
  assert_true(response_ok(verify(request)))
  let compare = Json::object({
    "action": Json::string("text_compare"),
    "actual": Json::string(@base64.encode(bytes)),
    "expected": Json::string(@base64.encode(bytes)),
    "equal": Json::boolean(true),
  }).stringify()
  assert_true(response_ok(verify(compare)))
}

///|
test "pixel verifier checks scene movement and resize bounds" {
  let previous = Json::object({
    "x": Json::number(40.0),
    "y": Json::number(0.0),
    "width": Json::number(120.0),
    "height": Json::number(72.0),
  })
  let active = Json::object({
    "action": Json::string("scene"),
    "stage": Json::string("active"),
    "png": Json::string(png_fixture(false, 40, 200, 100)),
    "previous": previous,
  })
  assert_true(response_ok(verify(active.stringify())))
  let moved = Json::object({
    "action": Json::string("scene"),
    "stage": Json::string("moved"),
    "png": Json::string(png_fixture(false, 50, 200, 100)),
    "previous": previous,
  })
  assert_true(response_ok(verify(moved.stringify())))
  let resized = Json::object({
    "action": Json::string("scene"),
    "stage": Json::string("resized"),
    "png": Json::string(png_fixture(false, 50, 200, 100)),
    "canvasWidth": Json::number(200.0),
    "canvasHeight": Json::number(100.0),
  })
  assert_true(response_ok(verify(resized.stringify())))
  let wrong = Json::object({
    "action": Json::string("scene"),
    "stage": Json::string("moved"),
    "png": Json::string(png_fixture(false, 48, 200, 100)),
    "previous": previous,
  })
  assert_true(!response_ok(verify(wrong.stringify())))
}

///|
test "pixel verifier crop and text negative contracts" {
  let crop = Json::object({
    "action": Json::string("crop"),
    "png": Json::string(solid_png(648, 104, b'\xff')),
    "width": Json::number(640.0),
  })
  assert_true(response_ok(verify(crop.stringify())))
  let small_crop = Json::object({
    "action": Json::string("crop"),
    "png": Json::string(solid_png(24, 104, b'\xff')),
    "width": Json::number(16.0),
  })
  assert_true(response_ok(verify(small_crop.stringify())))
  let capped_crop = Json::object({
    "action": Json::string("crop"),
    "png": Json::string(solid_png(648, 104, b'\xff')),
    "width": Json::number(1000.0),
  })
  assert_true(response_ok(verify(capped_crop.stringify())))
  let bad_crop = Json::object({
    "action": Json::string("crop"),
    "png": Json::string(solid_png(640, 100, b'\xff')),
    "width": Json::number(640.0),
  })
  assert_true(!response_ok(verify(bad_crop.stringify())))
  let data = Array::make(640 * 96 * 4, b'\xff')
  data[0] = b'\x00'
  let initial = Json::object({
    "action": Json::string("text_initial"),
    "data": Json::string(@base64.encode(Bytes::from_array(data))),
    "width": Json::number(640.0),
  })
  assert_true(response_ok(verify(initial.stringify())))
  data[0] = b'\xff'
  data[3] = b'\xfe'
  let blank = Json::object({
    "action": Json::string("text_blank"),
    "data": Json::string(@base64.encode(Bytes::from_array(data))),
    "width": Json::number(640.0),
  })
  assert_true(!response_ok(verify(blank.stringify())))
  data[3] = b'\xff'
  data[1] = b'\xfd'
  let rgb_blank = Json::object({
    "action": Json::string("text_blank"),
    "data": Json::string(@base64.encode(Bytes::from_array(data))),
    "width": Json::number(640.0),
  })
  assert_true(!response_ok(verify(rgb_blank.stringify())))
  let unequal = Json::object({
    "action": Json::string("text_compare"),
    "actual": Json::string(@base64.encode(Bytes::from_array([0, 0, 0, 0]))),
    "expected": Json::string(@base64.encode(Bytes::from_array([1, 0, 0, 0]))),
    "equal": Json::boolean(false),
  })
  assert_true(response_ok(verify(unequal.stringify())))
  let same_false = Json::object({
    "action": Json::string("text_compare"),
    "actual": Json::string(@base64.encode(Bytes::from_array([0, 0, 0, 0]))),
    "expected": Json::string(@base64.encode(Bytes::from_array([0, 0, 0, 0]))),
    "equal": Json::boolean(false),
  })
  assert_true(!response_ok(verify(same_false.stringify())))
  let different_true = Json::object({
    "action": Json::string("text_compare"),
    "actual": Json::string(@base64.encode(Bytes::from_array([0, 0, 0, 0]))),
    "expected": Json::string(@base64.encode(Bytes::from_array([1, 0, 0, 0]))),
    "equal": Json::boolean(true),
  })
  assert_true(!response_ok(verify(different_true.stringify())))
  let missing_equal = Json::object({
    "action": Json::string("text_compare"),
    "actual": Json::string(@base64.encode(Bytes::from_array([0, 0, 0, 0]))),
    "expected": Json::string(@base64.encode(Bytes::from_array([0, 0, 0, 0]))),
  })
  assert_true(!response_ok(verify(missing_equal.stringify())))
}

///|
test "pixel verifier rejects unknown action stage and invalid PNG" {
  assert_true(
    !response_ok(
      verify(Json::object({ "action": Json::string("unknown") }).stringify()),
    ),
  )
  let stage = Json::object({
    "action": Json::string("scene"),
    "stage": Json::string("initial"),
    "png": Json::string(
      @base64.encode(
        Bytes::from_array([b'n', b'o', b't', b' ', b'a', b' ', b'p', b'n', b'g']),
      ),
    ),
    "canvasWidth": Json::number(200.0),
    "canvasHeight": Json::number(100.0),
  })
  let invalid_result = verify(stage.stringify())
  assert_true(!response_ok(invalid_result))
  assert_true(invalid_result.contains("\"error\""))
}

///|
test "pixel verifier enforces DPR2 bounds" {
  let reference = Bytes::make(640 * 96 * 4, b'\x7f')
  let too_small = Json::object({
    "action": Json::string("dpr2"),
    "png": Json::string(solid_png(1280, 720, b'\x7f')),
    "reference": Json::string(@base64.encode(reference)),
  })
  assert_true(!response_ok(verify(too_small.stringify())))
}

///|
test "pixel verifier accepts DPR2 patterned pixels" {
  let reference_array : Array[Byte] = Array::make(640 * 96 * 4, b'\x00')
  for index = 0; index < reference_array.length(); index = index + 4 {
    reference_array[index] = (index / 4 % 251).to_byte()
    reference_array[index + 1] = (index / 16 % 239).to_byte()
    reference_array[index + 2] = (index / 64 % 233).to_byte()
    reference_array[index + 3] = b'\xff'
  }
  let reference = Bytes::from_array(reference_array)
  let image = Array::make(1296 * 720 * 4, b'\x00')
  for y in 0..<192 {
    for x in 0..<1280 {
      let actual = ((y + 16) * 1296 + x + 16) * 4
      let expected = (y / 2 * 640 + x / 2) * 4
      for channel in 0..<4 {
        image[actual + channel] = reference[expected + channel]
      }
    }
  }
  let request = Json::object({
    "action": Json::string("dpr2"),
    "png": Json::string(
      @base64.encode(
        @image.encode_png(@image.ImageData::{
          width: 1296,
          height: 720,
          data: Bytes::from_array(image),
        }),
      ),
    ),
    "reference": Json::string(@base64.encode(reference)),
  })
  assert_true(response_ok(verify(request.stringify())))
  image[(16 * 1296 + 16) * 4 + 1] = image[(16 * 1296 + 16) * 4 + 1] + 1
  let mutated = Json::object({
    "action": Json::string("dpr2"),
    "png": Json::string(
      @base64.encode(
        @image.encode_png(@image.ImageData::{
          width: 1296,
          height: 720,
          data: Bytes::from_array(image),
        }),
      ),
    ),
    "reference": Json::string(@base64.encode(reference)),
  })
  assert_true(!response_ok(verify(mutated.stringify())))
}
