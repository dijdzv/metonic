///|
fn check_composition_recovery() -> Unit raise {
  let element = @input_binding.input("rpc-user").unwrap()
  let accepted = Ref(true)
  let began = Ref(0)
  let session = @input_binding.start([{
    element: @input_binding.SingleLine(element),
    scroll: _ => (), focus: () => (),
    begin_composition: () => { began.val += 1; 1 },
    end_composition: () => (), preedit: _ => (), preview: (_, _) => 1,
    commit: (_, _, _) => if accepted.val { 1 } else { 0 },
  }], () => ())
  let target = query_target(element)
  accepted.val = false
  ignore(dispatch_event(target, event("input")))
  assert_eq(session.error(), 1)
  ignore(dispatch_event(target, composition_event("compositionstart")))
  assert_eq(began.val, 0)
  accepted.val = true
  ignore(dispatch_event(target, composition_event("compositionstart")))
  assert_eq(began.val, 1)
  assert_true(session.composing())
  assert_eq(session.error(), 1)
  ignore(dispatch_event(target, composition_event("compositionend")))
  assert_false(session.composing())
  session.stop()
}
