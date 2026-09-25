///|
fn Session::scroll_viewport(
  self : Session,
  x : Int,
  y : Int,
  delta : Int,
) -> Bool {
  guard !self.stopped &&
    delta != 0 &&
    self.application.viewport is Some(viewport) else {
    return false
  }
  let controls = self.presented
  for index = controls.length() - 1; index >= 0; index = index - 1 {
    let control = controls[index]
    if control.element.bounds.contains(x, y) &&
      control.clip.map(clip => clip.contains(x, y)).unwrap_or(true) {
      if control.kind is @app.Input(..) {
        return false
      }
      break
    }
  }
  if (viewport.scroll)(x, y, delta) {
    ignore(self.application.publish())
    self.notify()
    true
  } else {
    false
  }
}
