///|
#unsafe_skip_stub_check
fn runtime_exit(code : Int) = "moonbitlang/async" "runtime/exit"

///|
fn field(value : Json, key : String) -> Json? {
  match value {
    Json::Object(values) => values.get(key)
    _ => None
  }
}

///|
fn integer(value : Json, key : String, fallback : Int) -> Int {
  match field(value, key) {
    Some(Json::Number(number, ..)) => number.to_int()
    _ => fallback
  }
}

///|
fn ready(mode : String) -> Json {
  if mode == "bad-ready" {
    Json::object({
      "id": Json::number(0.0),
      "ok": Json::boolean(true),
      "session_id": Json::number(1.0),
    })
  } else {
    Json::object({
      "id": Json::number(0.0),
      "ok": Json::boolean(true),
      "session_id": Json::string("fixture-session"),
    })
  }
}

///|
fn response(id : Int, value : Json) -> Json {
  Json::object({
    "id": Json::number(id.to_double()),
    "ok": Json::boolean(true),
    "response": Json::object({
      "version": Json::number(1.0),
      "id": Json::number(id.to_double()),
      "ok": Json::boolean(true),
      "error": Json::null(),
      "state": Json::array([
        Json::number(260.0),
        Json::number(144.0),
        Json::number(120.0),
        Json::number(72.0),
        Json::number(0.0),
        Json::number(0.0),
        Json::number(640.0),
        Json::number(360.0),
      ]),
      "frame": Json::number(0.0),
    }),
    "value": value,
  })
}

///|
async fn write(value : Json) -> Unit {
  @stdio.stdout.write(value.stringify() + "\n")
}

///|
async fn write_bytes_all(data : Bytes) -> Bool {
  try {
    let mut offset = 0
    while offset < data.length() {
      let written = @stdio.stdout.write_once(
        data,
        offset~,
        len=data.length() - offset,
      )
      if written <= 0 {
        return false
      }
      offset += written
    }
    true
  } catch {
    _ => false
  }
}

///|
async fn main {
  let args = @env.args()
  let mode = if args.length() > 1 { args[1] } else { "normal" }
  if mode != "normal" &&
    mode != "bad-ready" &&
    mode != "bad-utf8-ready" &&
    mode != "partial-ready" &&
    mode != "bad-response" &&
    mode != "unknown-id" &&
    mode != "overlong" &&
    mode != "no-ready" &&
    mode != "nonzero" &&
    mode != "hang-close" {
    abort("unknown fixture mode")
  }
  if mode == "no-ready" {
    while @stdio.stdin.read_some(max_len=8192) is Some(_) {
      ()
    }
    return
  }
  if mode == "partial-ready" {
    @stdio.stdout.write("{\"id\":0,\"ok\":true")
    return
  }
  if mode == "bad-utf8-ready" {
    let prefix = @utf8.encode("{\"id\":0,\"ok\":true,\"session_id\":\"")
    let suffix = @utf8.encode("\"}\n")
    let bytes = prefix.to_array()
    bytes.push(0xff)
    for byte in suffix.iter() {
      bytes.push(byte)
    }
    ignore(write_bytes_all(Bytes::from_array(bytes)))
  } else {
    write(ready(mode))
  }
  if mode == "bad-ready" || mode == "bad-utf8-ready" {
    while @stdio.stdin.read_some(max_len=8192) is Some(_) {
      ()
    }
    return
  }
  let lines = @lines.Lines::new()
  let running = true
  while running && @stdio.stdin.read_some(max_len=8192) is Some(chunk) {
    for line in lines.feed(chunk) {
      match line {
        @lines.InputLine::TooLong =>
          write(
            Json::object({
              "id": Json::number(1.0),
              "ok": Json::boolean(false),
              "error": Json::string("overlong"),
            }),
          )
        @lines.InputLine::Line(bytes) => {
          if mode == "overlong" {
            for _ in 0..<8193 {
              if !write_bytes_all(Bytes::make(4096, b'x')) {
                return
              }
            }
            while @stdio.stdin.read_some(max_len=8192) is Some(_) {
              ()
            }
            return
          }
          let request = @json.parse(@utf8.decode(bytes)) catch { _ => continue }
          let id = integer(request, "id", 0)
          if mode == "bad-response" {
            write(
              Json::object({
                "id": Json::number(id.to_double()),
                "ok": Json::boolean(true),
                "response": Json::object({}),
              }),
            )
            while @stdio.stdin.read_some(max_len=8192) is Some(_) {
              ()
            }
            return
          } else if mode == "unknown-id" {
            write(response(id + 1, Json::null()))
            while @stdio.stdin.read_some(max_len=8192) is Some(_) {
              ()
            }
            return
          } else {
            write(response(id, Json::null()))
          }
        }
      }
    }
  }
  if mode == "hang-close" {
    @async.sleep(60000)
    return
  }
  if mode == "nonzero" {
    runtime_exit(19)
  }
  for line in lines.finish() {
    match line {
      @lines.InputLine::Line(bytes) => {
        let request = @json.parse(@utf8.decode(bytes)) catch { _ => continue }
        write(response(integer(request, "id", 0), Json::null()))
      }
      @lines.InputLine::TooLong => ()
    }
  }
}
