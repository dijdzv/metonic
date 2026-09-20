///|
fn notify() -> Unit {
  ignore(
    @input_binding.document_target().dispatch_event(
      @dom.Event::new("metonic-notes"),
    ),
  )
}
