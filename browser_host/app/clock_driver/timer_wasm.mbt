///|
fn host_set_timeout(callback : () -> Unit, delay : Int) -> Int {
  @input_binding.window().set_timeout(
    @input_dom.TimeoutCallback::new(callback),
    delay,
  )
}

///|
fn host_clear_timeout(timer : Int) -> Unit {
  @input_binding.window().clear_timeout(timer)
}
