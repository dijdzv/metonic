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
          let state = app.snapshot()
          let pixels = app.renderer.unwrap().capture_frame()
          Ok(Captured::{
            state,
            pixels,
            width: state.width,
            height: state.height,
            frame: state.frames,
          })
        } catch {
          error => Err(error)
        },
      )
    Edit(text, expected, result) =>
      if app.composition is Some(_) {
        result.val = Some("composition_active")
      } else if expected is Some(revision) &&
        revision != @semantics.revision(app.model.editor) {
        result.val = Some("stale_revision")
      } else {
        let reference = @semantics.snapshot(app.model.editor)[1].reference
        let error = match text {
          Some(text) =>
            @semantics.replace_selection(app.model.editor, reference, text)
          None => @semantics.delete_backward(app.model.editor, reference)
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
        revision != @semantics.revision(app.model.editor) {
        result.val = Some("stale_revision")
      } else {
        let reference = @semantics.snapshot(app.model.editor)[1].reference
        let error = @semantics.set_selection(
          app.model.editor,
          reference,
          start,
          end,
        )
        if error == "" {
          app.draw()
        }
        result.val = Some(error)
      }
  }
}
