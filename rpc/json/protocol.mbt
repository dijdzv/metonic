///|
pub struct Reply {
  status : Int
  body : Json
}

///|
pub struct Endpoint {
  id : String
  invoke : (Json) -> Reply
}

///|
pub fn reject(status : Int, code : String) -> Reply {
  {
    status,
    body: Json::object({
      "version": Json::number(1.0),
      "ok": Json::boolean(false),
      "error": Json::object({
        "kind": Json::string("protocol"),
        "code": Json::string(code),
      }),
    }),
  }
}

///|
pub fn[I : FromJson, O : ToJson, E] endpoint(
  binding : @rpc.Binding[I, O, E],
  error_code : (E) -> String,
) -> Endpoint {
  let invoke = (input : Json) => {
    try {
      let typed : I = @codec.from_json(input)
      match binding.call(typed) {
        Ok(output) =>
          {
            status: 200,
            body: Json::object({
              "version": Json::number(1.0),
              "ok": Json::boolean(true),
              "output": @codec.to_json(output),
            }),
          }
        Err(error) =>
          {
            status: 200,
            body: Json::object({
              "version": Json::number(1.0),
              "ok": Json::boolean(false),
              "error": Json::object({
                "kind": Json::string("domain"),
                "code": Json::string(error_code(error)),
              }),
            }),
          }
      }
    } catch {
      _ => reject(400, "invalid_input")
    }
  }
  { id: binding.procedure.id, invoke, }
}

// The pinned parser exposes its depth limit through a deprecated label; omitting it would relax the protocol bound.

///|
#warnings("-deprecated")
pub fn dispatch(endpoint : Endpoint, body : String) -> Reply {
  if @utf8.encode(body).length() > 65536 {
    reject(413, "request_too_large")
  } else {
    try {
      match @codec.parse(body, max_nesting_depth=32) {
        Json::Object(fields) =>
          match
            (
              fields.get("version"),
              fields.get("procedure"),
              fields.get("input"),
            ) {
            (
              Some(Json::Number(version, ..)),
              Some(Json::String(procedure)),
              Some(input),
            ) =>
              if version != 1.0 {
                reject(400, "invalid_request")
              } else if procedure != endpoint.id {
                reject(404, "unknown_procedure")
              } else {
                (endpoint.invoke)(input)
              }
            _ => reject(400, "invalid_request")
          }
        _ => reject(400, "invalid_json")
      }
    } catch {
      _ => reject(400, "invalid_json")
    }
  }
}

///|
pub fn[I : ToJson, O, E] request(
  procedure : @rpc.Procedure[I, O, E],
  input : I,
) -> Json {
  Json::object({
    "version": Json::number(1.0),
    "procedure": Json::string(procedure.id),
    "input": @codec.to_json(input),
  })
}

///|
pub(all) enum CallError[E] {
  Domain(E)
  Protocol(String)
  Remote(String)
} derive(Debug, Eq)

///|
pub fn[I, O : FromJson, E] response(
  _procedure : @rpc.Procedure[I, O, E],
  status : Int,
  body : Json,
  decode_error : (String) -> E?,
) -> Result[O, CallError[E]] {
  match body {
    Json::Object(fields) =>
      match (fields.get("version"), fields.get("ok")) {
        (Some(Json::Number(version, ..)), Some(Json::True)) =>
          if version != 1.0 || status < 200 || status >= 300 {
            Err(Protocol("invalid_response"))
          } else {
            match fields.get("output") {
              Some(output) =>
                Ok(@codec.from_json(output)) catch {
                  _ => Err(Protocol("invalid_response"))
                }
              None => Err(Protocol("invalid_response"))
            }
          }
        (Some(Json::Number(version, ..)), Some(Json::False)) =>
          if version != 1.0 {
            Err(Protocol("invalid_response"))
          } else {
            match fields.get("error") {
              Some(Json::Object(error)) =>
                match (error.get("kind"), error.get("code")) {
                  (Some(Json::String("domain")), Some(Json::String(code))) =>
                    if status != 200 {
                      Err(Protocol("invalid_response"))
                    } else {
                      match decode_error(code) {
                        Some(value) => Err(Domain(value))
                        None => Err(Remote(code))
                      }
                    }
                  (Some(Json::String("protocol")), Some(Json::String(code))) =>
                    Err(Protocol(code))
                  _ => Err(Protocol("invalid_response"))
                }
              _ => Err(Protocol("invalid_response"))
            }
          }
        _ => Err(Protocol("invalid_response"))
      }
    _ => Err(Protocol("invalid_response"))
  }
}
