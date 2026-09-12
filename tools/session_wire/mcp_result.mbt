///|
fn session_metadata(session : String, value : Json, omit_image : Bool) -> Json {
  let fields : Map[String, Json] = { "session_id": Json::string(session) }
  if value is Json::Object(source) {
    for key, item in source {
      if !omit_image || key != "image" {
        fields[key] = item
      }
    }
  }
  Json::object(fields)
}

///|
fn text_content(value : Json) -> Json {
  { "type": "text", "text": value.stringify() }
}

///|
#export_name("native_mcp_failure")
pub fn native_mcp_failure(session : String, message : String) -> String {
  let value : Json = {
    "content": [
      text_content({ "session_id": session, "ok": false, "error": message }),
    ],
    "isError": true,
  }
  value.stringify()
}

///|
#export_name("native_mcp_result")
pub fn native_mcp_result(
  session : String,
  response : String,
  image : String,
) -> String {
  let state = @json.parse(response) catch {
    _ => return native_mcp_failure(session, "invalid native MCP response")
  }
  let content = [text_content(session_metadata(session, state, false))]
  if image != "" {
    let image = @json.parse(image) catch {
      _ => return native_mcp_failure(session, "invalid native MCP image")
    }
    let mime = match field(image, "mimeType") {
      Json::String(value) if value != "" => value
      _ => "image/png"
    }
    content.push({
      "type": "image",
      "data": field(image, "data"),
      "mimeType": mime,
    })
  }
  let value : Json = {
    "content": content,
    "isError": field(state, "ok") == Json::boolean(false),
  }
  value.stringify()
}

///|
#export_name("window_mcp_result")
pub fn window_mcp_result(session : String, response : String) -> String {
  let state = @json.parse(response) catch {
    _ => {
      let error : Json = {
        "isError": true,
        "content": [{ "type": "text", "text": "invalid window MCP response" }],
      }
      return error.stringify()
    }
  }
  let content = [text_content(session_metadata(session, state, true))]
  if field(state, "image") is Json::Object(image) {
    content.push({
      "type": "image",
      "data": image.get("data").unwrap_or(Json::null()),
      "mimeType": image.get("mimeType").unwrap_or(Json::null()),
    })
    let metadata : Map[String, Json] = Map([])
    for key in ["width", "height", "frame", "source"] {
      if image.get(key) is Some(value) {
        metadata[key] = value
      }
    }
    content.push(text_content(Json::object(metadata)))
  }
  let result : Json = { "content": content }
  result.stringify()
}
