///|
async fn main {
  @window_host.run(
    @notes_application.create(@notes.create()),
    controller=Some(@application_control.control),
    hidden=true,
    report=_ => (),
  )
}
