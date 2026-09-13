///|
fn byte_length(code_units : Int) -> Int? {
  if code_units < 0 || code_units > 1073741823 {
    None
  } else {
    Some(code_units * 2)
  }
}

///|
#export_name("unpack")
pub fn unpack(packed : String) -> FixedArray[Byte] {
  let length = byte_length(packed.length()).unwrap()
  let result : FixedArray[Byte] = FixedArray::make(length, 0)
  // UTF-8 conversion would replace binary surrogate code units.
  for i = 0; i < packed.length(); i = i + 1 {
    let word = packed.get(i).unwrap().to_uint()
    result[i * 2] = word.to_byte()
    result[i * 2 + 1] = (word >> 8).to_byte()
  }
  result
}
