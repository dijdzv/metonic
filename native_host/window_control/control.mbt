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
priv struct ConnectionState {
  mut ended : Bool
  changed : @cond_var.Cond
}

///|
priv suberror SessionQueueOverflow

///|
async fn ConnectionState::wait_end(self : ConnectionState) -> String {
  defer self.changed.broadcast()
  while !self.ended {
    self.changed.wait()
  }
  "disconnected"
}

///|
async fn respond(
  handle : @ui.Handle,
  bytes : Bytes,
  last_id : Ref[Int],
  output : &@io.Writer,
  identity : String?,
  connection : ConnectionState,
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
async fn session(
  handle : @ui.Handle,
  input : &@io.Reader,
  output : &@io.Writer,
  identity : String?,
  frame_scope : String,
) -> Unit {
  let pending : @aqueue.Queue[@lines.InputLine] = @aqueue.Queue(
    kind=@aqueue.Blocking(64),
  )
  let connection = ConnectionState::{ ended: false, changed: @cond_var.Cond(), }
  defer pending.close(clear=true)
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      let lines = @lines.Lines::new(lf_only=true)
      defer {
        connection.ended = true
        connection.changed.broadcast()
        pending.close()
      }
      while input.read_some(max_len=1024) is Some(chunk) {
        for line in lines.feed(chunk) {
          // WhyNot: blocking admission would hide EOF behind a full request queue.
          if !pending.try_put(line) {
            raise SessionQueueOverflow
          }
        }
      }
      for line in lines.finish() {
        if !pending.try_put(line) {
          raise SessionQueueOverflow
        }
      }
    }
    let last_id = Ref(0)
    while true {
      let line = pending.get() catch {
        @aqueue.QueueAlreadyClosed => break
        error => raise error
      }
      match line {
        @lines.InputLine::Line(bytes) =>
          respond(
            handle, bytes, last_id, output, identity, connection, frame_scope,
          )
        @lines.InputLine::TooLong =>
          output.write("{\"id\":null,\"error\":\"line_too_long\"}\n")
      }
    }
  }
}

///|
async fn control(handle : @ui.Handle) -> Unit {
  let reservation = @fs.tmpdir(prefix="metonic-session")
  defer @async.protect_from_cancel(() => @fs.rmdir(reservation))
  let parts = reservation.replace_all(old="\\", new="/").split("/").to_array()
  let identity = parts[parts.length() - 1].to_owned()
  match @env.get_env_var("METONIC_DEV_PIPE") {
    None => {
      session(handle, @stdio.stdin, @stdio.stdout, None, identity) catch {
        SessionQueueOverflow =>
          @stdio.stderr.write("control request queue exceeded\n")
        error => raise error
      }
      (handle.apply)(@ui.Action::Close)
    }
    Some(name) => {
      let pipe = @pipe.WindowsPipe::listen(name)
      defer pipe.close()
      let discovery_path = reservation + "/session.json"
      let discovery : Json = {
        "protocol_version": 1,
        "session_id": identity,
        "pipe": pipe.path(),
      }
      defer @async.protect_from_cancel(() => {
        if @fs.exists(discovery_path) {
          @fs.remove(discovery_path)
        }
      })
      @fs.write_file(discovery_path, discovery.stringify())
      @stdio.stderr.write("METONIC_DEV_SESSION " + discovery_path + "\n")
      @stdio.stderr.write("METONIC_DEV_PIPE_READY " + pipe.path() + "\n")
      while true {
        pipe.accept()
        session(handle, pipe, pipe, Some(identity), identity) catch {
          error if @async.is_cancellation_error(error) => raise error
          error =>
            @stdio.stderr.write(
              "control connection ended: " + error.to_string() + "\n",
            )
        }
        pipe.disconnect()
      }
    }
  }
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
