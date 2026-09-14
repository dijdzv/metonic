///|
priv enum DevelopmentRequest {
  Barrier(Ref[Bool])
  Capture(Ref[Result[Captured, Error]?])
  CaptureRetained(Int64, Ref[Result[@gpu.RetainedCapture, Error]?])
  DisplayStatus(Int64, Ref[@gpu.DisplayStatus?])
  Edit(String?, Int?, Ref[String?])
  Select(Int, Int, Int?, Ref[String?])
}

///|
async fn App::dispatch_development(
  app : App,
  request : DevelopmentRequest,
) -> Unit {
  match request {
    DisplayStatus(id, result) =>
      result.val = Some(app.renderer.unwrap().poll_display_status(id))
    Barrier(applied) => applied.val = true
    CaptureRetained(id, result) =>
      result.val = Some(
        try {
          let renderer = app.renderer.unwrap()
          ignore(renderer.poll_display_confirmation(id))
          Ok(renderer.capture_retained(id))
        } catch {
          error => Err(error)
        },
      )
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
      if app.composition is Some(_) || app.ime_pointer.pending() {
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
      if app.composition is Some(_) || app.ime_pointer.pending() {
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
