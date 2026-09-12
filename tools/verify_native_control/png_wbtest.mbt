///|
fn png_contract_pattern(width : Int, height : Int) -> @image.ImageData {
  let data : Array[Byte] = []
  for y = 0; y < height; y = y + 1 {
    for x = 0; x < width; x = x + 1 {
      data.push((x * 17 + y * 13).to_byte())
      data.push((x * 7 + y * 29).to_byte())
      data.push((x * 3 + y * 31).to_byte())
      let alpha = match (x + y) % 3 {
        0 => 0
        1 => 127
        _ => 255
      }
      data.push(alpha.to_byte())
    }
  }
  @image.ImageData::{ width, height, data: Bytes::from_array(data), }
}

///|
fn png_contract_roundtrip(width : Int, height : Int) -> Unit raise Error {
  let source = png_contract_pattern(width, height)
  let encoded = @image.encode_png(source)
  let decoded = @image.decode_png(encoded)
  assert_eq(decoded.width, width)
  assert_eq(decoded.height, height)
  assert_eq(decoded.data, source.data)
}

///|
test "native control PNG contract small RGBA" {
  png_contract_roundtrip(3, 2)
}

///|
test "native control PNG contract large RGBA" {
  png_contract_roundtrip(257, 129)
}

///|
test "native control PNG rejects invalid data length" {
  let rejected = try {
    ignore(
      @image.encode_png(@image.ImageData::{
        width: 3,
        height: 2,
        data: Bytes::from_array([0]),
      }),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "native control PNG rejects invalid dimensions" {
  let rejected = try {
    ignore(
      @image.encode_png(@image.ImageData::{
        width: 0,
        height: 2,
        data: Bytes::new(0),
      }),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
