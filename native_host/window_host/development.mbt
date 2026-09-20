///|
priv enum DevelopmentRequest {
  Barrier(Ref[Bool])
  Capture(Ref[Result[Captured, Error]?], (Snapshot) -> Unit)
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
    Capture(result, observe) =>
      result.val = Some(
        try {
          let state = app.snapshot()
          observe(state)
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
        revision != @semantics.revision(app.host.editor) {
        result.val = Some("stale_revision")
      } else {
        let reference = app.host.default_input
        let error = match text {
          Some(text) =>
            @semantics.replace_selection(app.host.editor, reference, text)
          None => @semantics.delete_backward(app.host.editor, reference)
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
        revision != @semantics.revision(app.host.editor) {
        result.val = Some("stale_revision")
      } else {
        let reference = app.host.default_input
        let error = @semantics.set_selection(
          app.host.editor,
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
