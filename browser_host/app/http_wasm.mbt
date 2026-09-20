///|
fn http_notify() -> Unit {
  ignore(
    @input_binding.document_target().dispatch_event(
      @input_dom.Event::new("metonic-rpc", {
        bubbles: None,
        cancelable: None,
        composed: None,
      }),
    ),
  )
}
