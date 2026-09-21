///|
priv enum DevelopmentRequest {
  Operate(@semantics.NodeRef, ControlAction, Int, Ref[String?])
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
    Operate(target, action, revision, result) =>
      result.val = Some(app.operate_control(target, action, revision))
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
      } else if app.default_node() is Some(node) {
        let reference = node.reference
        let error = match text {
          Some(text) =>
            @semantics.replace_selection(app.host.editor, reference, text)
          None => @semantics.delete_backward(app.host.editor, reference)
        }
        if error == "" {
          app.draw()
        }
        result.val = Some(error)
      } else {
        result.val = Some("no_default_input")
      }
    Select(start, end, expected, result) =>
      if app.composition is Some(_) || app.ime_pointer.pending() {
        result.val = Some("composition_active")
      } else if expected is Some(revision) &&
        revision != @semantics.revision(app.host.editor) {
        result.val = Some("stale_revision")
      } else if app.default_node() is Some(node) {
        let reference = node.reference
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
      } else {
        result.val = Some("no_default_input")
      }
  }
}

///|
fn App::operate_control(
  app : App,
  target : @semantics.NodeRef,
  action : ControlAction,
  revision : Int,
) -> String raise {
  if app.composition is Some(_) || app.ime_pointer.pending() {
    return "composition_active"
  }
  if revision != @semantics.revision(app.host.editor) {
    return "stale_revision"
  }
  let node = match @semantics.node(app.host.editor, target) {
    Ok(node) => node
    Err(error) => return error
  }
  if !node.enabled {
    return "disabled"
  }
  let error = match action {
    ActivateControl => {
      if node.role != @semantics.Button {
        return "unsupported_action"
      }
      ignore(@semantics.focus(app.host.editor, target))
      if (app.host.activate)(target) is Some(action) {
        app.queue(ApplicationTask(action.request, action.gate))
      }
      ""
    }
    InsertText(text) =>
      @semantics.replace_selection(app.host.editor, target, text)
    DeleteBackward => @semantics.delete_backward(app.host.editor, target)
    SelectRange(start, end) =>
      @semantics.set_selection(app.host.editor, target, start, end)
  }
  if error == "" {
    if !(action is ActivateControl) {
      ignore(@semantics.focus(app.host.editor, target))
    }
    app.draw()
  }
  error
}
