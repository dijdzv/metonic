///|
fn host_set_timeout(callback : () -> Unit, delay : Int) -> Int {
  @input_binding.window()
  .set_timeout_with_function(
    http_timer_handler(callback),
    delay,
    @input_dom.JsValue::undefined(),
  )
  .unwrap()
}

///|
fn host_clear_timeout(timer : Int) -> Unit {
  @input_binding.window().clear_timeout_with_id(timer)
}

///|
extern "js" fn http_timer_handler(callback : () -> Unit) -> @input_dom.Function =
  #| callback => callback
