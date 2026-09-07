///|
struct Request {
  id : Int
  op : String
  text : String?
  user_id : String?
  selection_start : Int?
  selection_end : Int?
  expected_semantic_revision : Int?
} derive(FromJson)

///|
async fn respond(
  handle : @ui.Handle,
  bytes : Bytes,
  last_id : Ref[Int],
) -> Unit {
  let request : Request = @json.from_json(@json.parse(@utf8.decode(bytes))) catch {
    _ => {
      @stdio.stdout.write("{\"id\":null,\"error\":\"invalid_request\"}\n")
      return
    }
  }
  let mut error = ""
  let mut captured_image : Json = Json::null()
  if request.id < 1 {
    error = "invalid_id"
  } else if request.id <= last_id.val {
    error = "duplicate_id"
  } else {
    last_id.val = request.id
    match request.op {
      "snapshot" => ()
      "capture" => {
        let captured = (handle.capture)()
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
  let state = (handle.inspect)()
  let response : Json = {
    "id": request.id,
    "error": error,
    "x": state.x,
    "y": state.y,
    "text": state.text,
    "semantic_revision": state.semantic_revision,
    "selection_start": state.selection_start,
    "selection_end": state.selection_end,
    "selection_anchor": state.selection_anchor,
    "caret": state.caret,
    "frames": state.frames,
    "task_status": state.task_status,
    "rpc_result": state.rpc_result,
    "composing": state.composing,
    "preedit": state.preedit,
    "preedit_cursor": state.preedit_cursor,
    "ime_requested_x": state.ime_requested_x,
    "ime_requested_y": state.ime_requested_y,
    "image": captured_image,
  }
  @stdio.stdout.write(response.stringify() + "\n")
}

///|
async fn control(handle : @ui.Handle) -> Unit {
  let lines = @lines.Lines::new(lf_only=true)
  let last_id = Ref(0)
  while @stdio.stdin.read_some(max_len=1024) is Some(chunk) {
    for line in lines.feed(chunk) {
      match line {
        @lines.InputLine::Line(bytes) => respond(handle, bytes, last_id)
        @lines.InputLine::TooLong =>
          @stdio.stdout.write("{\"id\":null,\"error\":\"line_too_long\"}\n")
      }
    }
  }
  for line in lines.finish() {
    match line {
      @lines.InputLine::Line(bytes) => respond(handle, bytes, last_id)
      @lines.InputLine::TooLong =>
        @stdio.stdout.write("{\"id\":null,\"error\":\"line_too_long\"}\n")
    }
  }
  (handle.apply)(@ui.Action::Close)
}

///|
async fn main {
  @ui.run(
    controller=Some(control),
    hidden=@env.get_env_var("METONIC_DEV_HIDDEN") == Some("1"),
    report=_ => (),
  )
}
