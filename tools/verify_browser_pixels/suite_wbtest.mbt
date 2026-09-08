///|
extern "js" fn wrong_target_host() -> BrowserHost =
  #| () => async (request) => ({ target: 'wasm-gc', pageerrors: [] })

///|
async test "suite rejects a result belonging to a different target" {
  try
    run_suite(
      wrong_target_host(),
      "{\"backend\":\"default\",\"browser\":\"test\",\"node\":\"test\"}",
    )
  catch {
    VerifyFailure::Failure(message) =>
      assert_eq(message, "scene target mismatch")
    error => raise error
  } noraise {
    _ => fail("wrong target accepted")
  }
}

///|
extern "js" fn incomplete_dpr_host() -> BrowserHost =
  #| () => async (request) => {
  #|   switch (request.op) {
  #|     case 'scene': return { target: request.target, pageerrors: [] };
  #|     case 'failures': return [];
  #|     case 'default-target': return 'wasm-gc';
  #|     case 'editor-flow': return { preview: { text: 'A😀B', display: 'A日本B' }, committed: { text: 'A日本B', start: 3, end: 3 }, reset: { text: '日本語の描画を確認します ABC 123' }, stopped: { text: '' } };
  #|     case 'rpc': return { text: request.after_text ?? request.text, result: request.mode === 'cancel' ? '' : request.mode === 'replace' || request.user !== '1' ? '\nRPC: domain:not_found' : '\n月兎', status: request.mode === 'cancel' ? 4 : request.mode === 'replace' || request.user !== '1' ? 3 : 2 };
  #|     case 'text': return { summary: { target: request.target }, reference: 'reference' };
  #|     case 'dpr': return false;
  #|     default: throw new Error('suite continued past failed DPR');
  #|   }
  #| }

///|
async test "suite does not report success when DPR did not complete" {
  try
    run_suite(
      incomplete_dpr_host(),
      "{\"backend\":\"default\",\"browser\":\"test\",\"node\":\"test\"}",
    )
  catch {
    VerifyFailure::Failure(message) =>
      assert_eq(message, "DPR scenario did not complete")
    error => raise error
  } noraise {
    _ => fail("incomplete DPR accepted")
  }
}
