///|
extern "js" fn failing_host() -> BrowserHost =
  #| () => async (request) => { throw new Error(`host rejected ${request.op}`); }

///|
async test "failure scenario propagates failure to create its first page" {
  try run_failures(failing_host()) catch {
    VerifyFailure::Failure(message) => {
      assert_true(message.contains("host rejected open"))
      assert_true(message.contains("browser operation"))
    }
    error => raise error
  } noraise {
    _ => fail("host failure was swallowed")
  }
}

///|
extern "js" fn failure_sequence_host() -> BrowserHost =
  #| () => {
  #|   let target, stopped = false, released = false;
  #|   return async (request) => {
  #|     if (request.op === 'open') { stopped = false; released = false; }
  #|     if (request.op === 'goto') target = request.target;
  #|     if (request.op === 'stop') stopped = true;
  #|     if (request.op === 'release') {
  #|       if (!stopped) throw new Error('release before stop');
  #|       released = true;
  #|     }
  #|     if (request.op === 'observe') return { status: stopped ? 'Stopped.' : target === 'invalid' ? 'Unknown target' : 'Unable to fetch', submitted: released ? 1 : 0, errors: [], resetDisabled: true, stopDisabled: true };
  #|     return null;
  #|   };
  #| }

///|
async test "failure scenario rejects a frame submitted after held response release" {
  try run_failures(failure_sequence_host()) catch {
    VerifyFailure::Failure(message) =>
      assert_eq(message, "initialization submitted a frame")
    error => raise error
  } noraise {
    _ => fail("late initialization frame was accepted")
  }
}
