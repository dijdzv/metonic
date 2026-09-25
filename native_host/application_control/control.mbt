///|
priv struct Target {
  session : Int
  window : Int
  id : Int
  generation : Int
} derive(FromJson)

///|
priv struct Request {
  id : Int
  op : String
  session_id : String?
  target : Target?
  expected_semantic_revision : Int?
  text : String?
  selection_start : Int?
  selection_end : Int?
} derive(FromJson)

///|
fn controls(state : @host.Snapshot) -> Json {
  Json::array(
    state.controls.map(node => {
      let target = node.reference
      {
        "target": {
          "session": target.session,
          "window": target.window,
          "id": target.id,
          "generation": target.generation,
        },
        "role": match node.role {
          @semantics.Label => "label"
          @semantics.Button => "button"
          @semantics.TextInput => "text_input"
        },
        "name": node.name,
        "value": node.value,
        "enabled": node.enabled,
        "focused": node.focused,
        "selection_start": node.selection_start,
        "selection_end": node.selection_end,
      }
    }),
  )
}

///|
async fn respond(
  handle : @host.Handle,
  bytes : Bytes,
  last_id : Ref[Int],
  output : &@io.Writer,
  identity : String?,
) -> Unit {
  let request : Request = @json.from_json(@json.parse(@utf8.decode(bytes))) catch {
    _ => {
      output.write("{\"id\":null,\"error\":\"invalid_request\"}\n")
      return
    }
  }
  let mut error = ""
  let mut image : Json = Json::null()
  let mut captured : @host.Snapshot? = None
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
      "capabilities" | "snapshot" => ()
      "capture" => {
        let capture = (handle.capture)(_ => ())
        captured = Some(capture.state)
        let png = @image.encode_png(@image.ImageData::{
          width: capture.width,
          height: capture.height,
          data: capture.pixels,
        })
        image = {
          "data": @base64.encode(png),
          "mimeType": "image/png",
          "width": capture.width,
          "height": capture.height,
          "frame": capture.frame,
          "source": "shared_offscreen_pass",
        }
      }
      "insert" | "backspace" | "select" | "activate" =>
        match (request.target, request.expected_semantic_revision) {
          (Some(target), Some(revision)) => {
            let action : @host.ControlAction? = match request.op {
              "insert" => request.text.map(text => @host.InsertText(text))
              "backspace" => Some(@host.DeleteBackward)
              "activate" => Some(@host.ActivateControl)
              _ =>
                match (request.selection_start, request.selection_end) {
                  (Some(start), Some(end)) =>
                    Some(@host.SelectRange(start, end))
                  _ => None
                }
            }
            error = match action {
              Some(action) =>
                (handle.operate)(
                  {
                    session: target.session,
                    window: target.window,
                    id: target.id,
                    generation: target.generation,
                  },
                  action,
                  revision,
                )
              None => "invalid_arguments"
            }
          }
          _ => error = "target_and_revision_required"
        }
      _ => error = "unknown_operation"
    }
  }
  let state = captured.unwrap_or_else(() => (handle.inspect)())
  let response : Json = {
    "id": request.id,
    "error": error,
    "protocol_version": 1,
    "application_protocol": 1,
    "session_id": identity.unwrap_or("stdio"),
    "operations": [
      "snapshot", "capture", "insert", "backspace", "select", "activate",
    ],
    "semantic_revision": state.semantic_revision,
    "controls": controls(state),
    "frames": state.frames,
    "width": state.width,
    "height": state.height,
    "composing": state.composing,
    "closed": state.closed,
    "diagnostics": state.diagnostics.unwrap_or(Json::null()),
    "image": image,
  }
  output.write(response.stringify() + "\n")
}

///|
pub async fn control(handle : @host.Handle) -> Unit {
  @transport.run(
    (bytes, last_id, output, identity, _connection, _frame_scope) => {
      respond(handle, bytes, last_id, output, identity)
    },
    () => (handle.apply)(@host.Close),
  )
}
