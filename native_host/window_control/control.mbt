///|
struct Request {
  id : Int
  op : String
  text : String?
  user_id : String?
  selection_start : Int?
  selection_end : Int?
  expected_semantic_revision : Int?
  session_id : String?
  semantic_revision : Int?
  timeout_ms : Int?
  frame_id : String?
  frame_scope : String?
} derive(FromJson)

///|
async fn respond(
  handle : @ui.Handle,
  bytes : Bytes,
  last_id : Ref[Int],
  output : &@io.Writer,
  identity : String?,
  connection : @transport.ConnectionState,
  frame_scope : String,
) -> Unit {
  let request : Request = @json.from_json(@json.parse(@utf8.decode(bytes))) catch {
    _ => {
      output.write("{\"id\":null,\"error\":\"invalid_request\"}\n")
      return
    }
  }
  let mut error = ""
  let mut captured_image : Json = Json::null()
  let mut captured_state : @ui.Snapshot? = None
  if request.id < 1 {
    error = "invalid_id"
  } else if identity is Some(expected) &&
    request.op != "capabilities" &&
    request.session_id != Some(expected) {
    error = "stale_session"
  } else if request.id <= last_id.val {
    error = "duplicate_id"
  } else {
    last_id.val = request.id
    match request.op {
      "snapshot" | "capabilities" => ()
      "wait_display" =>
        if request.frame_scope != Some(frame_scope) {
          error = "stale_frame_scope"
        } else {
          let frame_id = match request.frame_id {
            Some(value) => @string.parse_int64(value) catch { _ => 0L }
            None => 0L
          }
          match request.timeout_ms {
            Some(timeout) =>
              error = @async.any([
                () => (handle.wait_display)(frame_id, timeout),
                () => connection.wait_end(),
              ])
            None => error = "invalid_wait"
          }
        }
      "wait_semantic" =>
        match (request.semantic_revision, request.timeout_ms) {
          (Some(revision), Some(timeout)) =>
            error = @async.any([
              () => (handle.wait_semantic)(revision, timeout),
              () => connection.wait_end(),
            ])
          _ => error = "invalid_wait"
        }
      "capture" => {
        let captured = (handle.capture)()
        captured_state = Some(captured.state)
        let png = @image.encode_png(@image.ImageData::{
          width: captured.width,
          height: captured.height,
          data: captured.pixels,
        })
        captured_image = {
          "data": @base64.encode(png),
          "mimeType": "image/png",
          "width": captured.width,
          "height": captured.height,
          "frame": captured.frame,
          "source": "shared_offscreen_pass",
        }
      }
      "capture_retained" =>
        if request.frame_scope != Some(frame_scope) {
          error = "stale_frame_scope"
        } else {
          let frame_id = match request.frame_id {
            Some(value) => @string.parse_int64(value) catch { _ => 0L }
            None => 0L
          }
          try {
            let captured = (handle.capture_retained)(frame_id)
            let png = @image.encode_png(@image.ImageData::{
              width: captured.width,
              height: captured.height,
              data: captured.pixels,
            })
            captured_image = {
              "data": @base64.encode(png),
              "mimeType": "image/png",
              "width": captured.width,
              "height": captured.height,
              "frame_id": captured.id.to_string(),
              "generation": captured.generation.to_string(),
              "display_scale": captured.display_scale,
              "frame_scope": frame_scope,
              "source": "retained_surface_copy",
              "display_completion_confirmed": captured.display_confirmed,
            }
          } catch {
            @gpu.RetainedFrameError::InvalidFrame => error = "invalid_frame"
            @gpu.RetainedFrameError::FrameNotSubmitted =>
              error = "frame_not_submitted"
            @gpu.RetainedFrameError::FrameEvicted => error = "frame_evicted"
            @gpu.RetainedFrameError::RetentionUnavailable =>
              error = "retention_unavailable"
            cause => raise cause
          }
        }
      "insert" =>
        match request.text {
          Some(text) =>
            error = (handle.edit)(
              Some(text),
              request.expected_semantic_revision,
            )
          None => error = "missing_text"
        }
      "backspace" =>
        error = (handle.edit)(None, request.expected_semantic_revision)
      "select" =>
        match (request.selection_start, request.selection_end) {
          (Some(start), Some(end)) =>
            error = (handle.select)(
              start,
              end,
              request.expected_semantic_revision,
            )
          _ => error = "missing_selection"
        }
      "start_update" => (handle.apply)(@ui.Action::StartUpdate)
      "load_user" =>
        (handle.apply)(@ui.Action::LoadUser(request.user_id.unwrap_or("1")))
      "cancel_update" => (handle.apply)(@ui.Action::CancelUpdate)
      _ => error = "unknown_operation"
    }
  }
  let state = match captured_state {
    Some(state) => state
    None => (handle.inspect)()
  }
  let response : Json = {
    "id": request.id,
    "error": error,
    "x": state.x,
    "y": state.y,
    "text": state.text,
    "semantic_revision": state.semantic_revision,
    "scene_revision": state.scene_revision,
    "selection_start": state.selection_start,
    "selection_end": state.selection_end,
    "selection_anchor": state.selection_anchor,
    "caret": state.caret,
    "frames": state.frames,
    "retained_frame_id": (handle.retained_frame_id)().to_string(),
    "frame_scope": frame_scope,
    "host_input_events": state.input.to_json(),
    "task_status": state.task_status,
    "rpc_result": state.rpc_result,
    "view": state.view.snapshot(),
    "composing": state.composing,
    "preedit": state.preedit,
    "preedit_cursor": state.preedit_cursor,
    "ime_events": state.ime_events,
    "raw_ime_events": state.raw_ime_events,
    "raw_ime_dropped": state.raw_ime_dropped,
    "ime_dropped": state.ime_dropped,
    "ime_requested_x": state.ime_requested_x,
    "ime_requested_y": state.ime_requested_y,
    "image": captured_image,
  }
  if identity is Some(value) {
    guard! response is Json::Object(fields)
    fields["session_id"] = Json::string(value)
    fields["protocol_version"] = Json::number(1)
  }
  output.write(response.stringify() + "\n")
}

///|
async fn control(handle : @ui.Handle) -> Unit {
  @transport.run(
    (bytes, last_id, output, identity, connection, frame_scope) => {
      respond(handle, bytes, last_id, output, identity, connection, frame_scope)
    },
    () => (handle.apply)(@ui.Action::Close),
  )
}

///|
pub async fn run(
  display_feedback? : ((@wgpu.Surface) -> @gpu.DisplayObservation)? = None,
) -> Unit {
  @ui.run(
    display_feedback~,
    controller=Some(control),
    hidden=@env.get_env_var("METONIC_DEV_HIDDEN") == Some("1"),
    report=_ => (),
  )
}
