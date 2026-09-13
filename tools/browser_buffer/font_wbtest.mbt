///|
test "font words preserve little endian order and pad only the tail" {
  let words : Array[Int] = []
  assert_true(
    transfer_font_words([0, 127, 128, 255, 42, 255, 128], word => {
      words.push(word)
      1
    }),
  )
  assert_eq(words, [0xFF807F00, 0x0080FF2A])
}

///|
test "rejected font word stops further delivery" {
  let mut calls = 0
  assert_false(
    transfer_font_words(FixedArray::make(12, 1), _ => {
      calls += 1
      if calls == 2 {
        0
      } else {
        1
      }
    }),
  )
  assert_eq(calls, 2)
}

///|
test "empty and oversized fonts never call receiver" {
  let mut calls = 0
  let inputs : Array[FixedArray[Byte]] = [
    FixedArray::make(0, 0),
    FixedArray::make(16777217, 0),
  ]
  for bytes in inputs {
    assert_false(
      transfer_font_words(bytes, _ => {
        calls += 1
        1
      }),
    )
  }
  assert_eq(calls, 0)
}
