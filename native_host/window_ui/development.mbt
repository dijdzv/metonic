///|
priv enum DevelopmentRequest {
  Barrier(Ref[Bool])
  Capture(Ref[Result[Captured, Error]?])
  Edit(String?, Int?, Ref[String?])
  Select(Int, Int, Int?, Ref[String?])
}

///|
async fn App::dispatch_development(
  app : App,
  request : DevelopmentRequest,
) -> Unit {
  match request {
    Barrier(applied) => applied.val = true
    Capture(result) =>
      result.val = Some(
        try {
          let pixels = app.renderer.unwrap().capture_frame()
          Ok(Captured::{
            pixels,
            width: @scene.field(app.state, 6),
            height: @scene.field(app.state, 7),
            frame: app.diagnostics.frames,
          })
        } catch {
          error => Err(error)
        },
      )
    Edit(text, expected, result) =>
      if app.composition is Some(_) {
        result.val = Some("composition_active")
      } else if expected is Some(revision) &&
        revision != @semantics.revision(app.editor) {
        result.val = Some("stale_revision")
      } else {
        let reference = @semantics.snapshot(app.editor)[1].reference
        let error = match text {
          Some(text) =>
            @semantics.replace_selection(app.editor, reference, text)
          None => @semantics.delete_backward(app.editor, reference)
        }
        if error == "" {
          app.draw()
        }
        result.val = Some(error)
      }
    Select(start, end, expected, result) =>
      if app.composition is Some(_) {
        result.val = Some("composition_active")
      } else if expected is Some(revision) &&
        revision != @semantics.revision(app.editor) {
        result.val = Some("stale_revision")
      } else {
        let reference = @semantics.snapshot(app.editor)[1].reference
        let error = @semantics.set_selection(app.editor, reference, start, end)
        if error == "" {
          app.draw()
        }
        result.val = Some(error)
      }
  }
}
