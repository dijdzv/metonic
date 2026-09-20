///|
fn host_notify(kind : String) -> Unit {
  ignore(
    @input_binding.document_target().dispatch_event(@input_dom.Event::new(kind)),
  )
}
