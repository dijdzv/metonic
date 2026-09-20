///|
fn move_focus(host : @host_application.Application, reverse : Bool) -> Unit {
  @host_application.move_focus(host.editor, (host.focus_order)(), reverse)
}
