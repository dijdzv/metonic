///|
extern "js" fn fixture(kind : Int) -> BrowserApi =
  #| (kind) => {
  #|   const initial = [260, 144, 120, 72, 0, 0, 640, 360];
  #|   const values = kind === 1 ? [0, 0, 0, 0, 0, 0, 0, 0] : [...initial];
  #|   const api = {
  #|     init() {},
  #|     resize() { return kind === 2 ? 0 : 1; },
  #|     move_to() { return 0; },
  #|     activate() {},
  #|     field(index) { return values[index] ?? -1; },
  #|   };
  #|   if (kind === 0) delete api.move_to;
  #|   return api;
  #| }

///|
extern "js" fn throws_error(f : () -> Unit) -> Bool =
  #| (f) => {
  #|   try {
  #|     f();
  #|     return false;
  #|   } catch (error) {
  #|     return error instanceof Error;
  #|   }
  #| }

///|
fn raised(f : () -> Unit raise Error) -> String? {
  try {
    f()
    None
  } catch {
    Failure(message) => Some(message)
    _ => Some("foreign error")
  }
}

///|
test "browser verifier rejects missing export fixture" {
  match raised(fn() raise Error { verify_checked(fixture(0), fixture(0)) }) {
    Some(message) =>
      assert_true(message.contains("move_to") || message.contains("export"))
    None => assert_true(false)
  }
}

///|
test "browser verifier rejects invalid initial state fixture" {
  match raised(fn() raise Error { verify_checked(fixture(1), fixture(1)) }) {
    Some(message) => assert_true(message.contains("browser state mismatch"))
    None => assert_true(false)
  }
}

///|
test "browser verifier rejects incorrect resize result fixture" {
  match raised(fn() raise Error { verify_checked(fixture(2), fixture(2)) }) {
    Some(message) => assert_true(message.contains("resize rejected"))
    None => assert_true(false)
  }
}

///|
test "browser verifier public boundary throws JavaScript Error" {
  assert_true(throws_error(fn() { verify(fixture(1), fixture(1)) }))
}
