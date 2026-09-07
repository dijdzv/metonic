///|
extern "js" fn fake_page() -> Page =
  #| () => ({ evaluate: async () => ({ task: [] }) })

///|
suberror TestFailure {
  Failure(String)
}

///|
fn expect_failure(
  f : () -> Unit raise Error,
  expected : String,
) -> Unit raise Error {
  let mut message : String? = None
  f() catch {
    error => message = Some(@debug.to_string(error))
  }
  match message {
    Some(value) => assert_true(value.contains(expected))
    None => raise TestFailure::Failure("expected verifier rejection")
  }
}

///|
test "snapshot validator rejects malformed snapshot" {
  expect_failure(
    fn() raise Error { ignore(state(@json.parse("{\"task\":[]}"))) },
    "length",
  )
}

///|
test "pixel validator rejects empty and out of range bounds" {
  expect_failure(
    fn() raise Error { check_pixel_bounds(0, 10, 0, 0, 0, 1) },
    "empty screenshot",
  )
  expect_failure(
    fn() raise Error { check_pixel_bounds(100, 100, 0, 0, -1, 10) },
    "empty teal",
  )
}

///|
fn png_fixture(teal : Bool, x0 : Int) -> String raise Error {
  let data : Array[Byte] = Array::make(200 * 4, b'\x05')
  for x = 0; x < 200; x = x + 1 {
    let active = teal && x >= x0 && x < x0 + 120
    let color = if active {
      [b'\x00', b'\xc8', b'\xc8', b'\xff']
    } else {
      [b'\x05', b'\x14', b'\x26', b'\xff']
    }
    for channel = 0; channel < 4; channel = channel + 1 {
      data[x * 4 + channel] = color[channel]
    }
  }
  @base64.encode(
    @image.encode_png(@image.ImageData::{
      width: 200,
      height: 1,
      data: Bytes::from_array(data),
    }),
  )
}

///|
test "PNG checker validates decoded teal bounds" {
  check_png(png_fixture(true, 40), 40)
  expect_failure(
    fn() raise Error { check_png(png_fixture(true, 70), 40) },
    "teal x",
  )
  expect_failure(
    fn() raise Error { check_png(png_fixture(false, 40), 40) },
    "empty teal",
  )
}

///|
test "text integer parser rejects fractions and invalid values" {
  expect_failure(
    fn() raise Error { ignore(text_int("1.5", "revision")) },
    "invalid integer",
  )
  expect_failure(
    fn() raise Error { ignore(text_int("NaN", "revision")) },
    "invalid integer",
  )
  expect_failure(
    fn() raise Error {
      ignore(int_field(@json.parse("{\"pending\":null}"), "pending"))
    },
    "missing integer",
  )
}

///|
async test "exported verifier rejects malformed page snapshot" {
  @moonbitlang/async.with_timeout(2000, async fn() {
    try ignore(verify(fake_page(), "js", ".work").wait()) catch {
      error =>
        assert_true(
          error.to_string().contains("VerifyFailure"),
          msg=error.to_string(),
        )
    } noraise {
      _ => raise TestFailure::Failure("verifier unexpectedly resolved")
    }
  })
}
