///|
struct Request {
  id : Int
  op : String
  text : String?
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
  if request.id < 1 {
    error = "invalid_id"
  } else if request.id <= last_id.val {
    error = "duplicate_id"
  } else {
    last_id.val = request.id
    match request.op {
      "snapshot" => ()
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
      "start_update" => (handle.apply)(@ui.Action::StartUpdate)
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
    "frames": state.frames,
    "task_status": state.task_status,
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
