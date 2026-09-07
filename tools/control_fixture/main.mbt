///|
/// The async runtime export is used because this Wasm-only fixture must preserve
/// the requested process exit code without adding a C or JavaScript shim.
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
fn int_field(value : Json, key : String, fallback : Int) -> Int {
  match field(value, key) {
    Some(Json::Number(n, ..)) => n.to_int()
    _ => fallback
  }
}

///|
fn state(revision : Int, width : Int, height : Int) -> Json {
  Json::array([
    Json::number(260.0),
    Json::number(144.0),
    Json::number(120.0),
    Json::number(72.0),
    Json::number(0.0),
    Json::number(revision.to_double()),
    Json::number(width.to_double()),
    Json::number(height.to_double()),
  ])
}

///|
fn response(
  id : Int,
  ok : Bool,
  revision : Int,
  width : Int,
  height : Int,
  extra : Array[(String, Json)],
) -> Json {
  let fields : Map[String, Json] = Map([
    ("version", Json::number(1.0)),
    ("id", Json::number(id.to_double())),
    ("ok", Json::boolean(ok)),
    ("state", state(revision, width, height)),
    ("error", Json::null()),
    ("frame", Json::number(0.0)),
  ])
  for entry in extra {
    fields[entry.0] = entry.1
  }
  Json::object(fields)
}

///|
async fn send(mutex : @async.Mutex, value : Json) -> Unit {
  mutex.acquire()
  defer mutex.release()
  @stdio.stdout.write(value.stringify() + "\n")
}

///|
async fn raw(mutex : @async.Mutex, value : String) -> Unit {
  mutex.acquire()
  defer mutex.release()
  @stdio.stdout.write(value + "\n")
}

///|
async fn delayed(
  mutex : @async.Mutex,
  request : Json,
  revision : Ref[Int],
  width : Ref[Int],
  height : Ref[Int],
) -> Unit {
  @async.sleep(int_field(request, "ms", 50))
  let value = match field(request, "value") {
    Some(value) => value
    _ => Json::null()
  }
  send(
    mutex,
    response(
      int_field(request, "id", 0),
      true,
      revision.val,
      width.val,
      height.val,
      [("value", value)],
    ),
  )
}

///|
async fn dispatch(
  group : @async.TaskGroup[Unit],
  mutex : @async.Mutex,
  request : Json,
  revision : Ref[Int],
  width : Ref[Int],
  height : Ref[Int],
) -> Bool {
  let id = int_field(request, "id", 0)
  let op = match field(request, "op") {
    Some(Json::String(value)) => value
    _ => ""
  }
  if op == "shutdown" {
    send(mutex, response(id, true, revision.val, width.val, height.val, []))
    false
  } else if op == "delay" {
    group.spawn_bg() <| () => {
      delayed(mutex, request, revision, width, height)
    }
    true
  } else if op == "exit" {
    runtime_exit(int_field(request, "code", 17))
    true
  } else if op == "stderrFlood" {
    @stdio.stderr.write(
      String::from_array(Array::make(int_field(request, "bytes", 65536), 'x')),
    )
    send(mutex, response(id, true, revision.val, width.val, height.val, []))
    true
  } else if op == "malformed" {
    raw(mutex, "{malformed json}")
    true
  } else if op == "unknownID" {
    send(
      mutex,
      response(id + 123, true, revision.val, width.val, height.val, []),
    )
    true
  } else if op == "oversize" {
    raw(
      mutex,
      Json::object({
        "id": Json::number(id.to_double()),
        "value": Json::string(
          String::from_array(
            Array::make(int_field(request, "bytes", 2 * 1024 * 1024), 'x'),
          ),
        ),
      }).stringify(),
    )
    true
  } else if op == "echo" {
    send(
      mutex,
      response(id, true, revision.val, width.val, height.val, [
        ("value", request),
      ]),
    )
    true
  } else if op == "snapshot" {
    send(mutex, response(id, true, revision.val, width.val, height.val, []))
    true
  } else if op == "resize" {
    width.val = int_field(request, "width", 640)
    height.val = int_field(request, "height", 360)
    revision.val += 1
    send(mutex, response(id, true, revision.val, width.val, height.val, []))
    true
  } else {
    send(
      mutex,
      response(id, false, revision.val, width.val, height.val, [
        ("error", Json::string("unknown operation: " + op)),
      ]),
    )
    true
  }
}

///|
async fn parse_dispatch(
  group : @async.TaskGroup[Unit],
  mutex : @async.Mutex,
  bytes : Bytes,
  revision : Ref[Int],
  width : Ref[Int],
  height : Ref[Int],
) -> Bool {
  let request = @json.parse(@utf8.decode(bytes)) catch {
    _ => {
      send(
        mutex,
        Json::object({
          "id": Json::string("malformed-response"),
          "error": Json::string("malformed request"),
        }),
      )
      return true
    }
  }
  dispatch(group, mutex, request, revision, width, height)
}

///|
async fn main {
  let mutex = @async.Mutex::Mutex()
  let revision : Ref[Int] = { val: 0, }
  let width : Ref[Int] = { val: 640, }
  let height : Ref[Int] = { val: 360, }
  @async.with_task_group() <| group => {
    let lines = @lines.Lines::new()
    let mut running = true
    while running && @stdio.stdin.read_some(max_len=8192) is Some(chunk) {
      for line in lines.feed(chunk) {
        if !running {
          break
        }
        match line {
          @lines.InputLine::TooLong =>
            send(
              mutex,
              Json::object({
                "id": Json::string("malformed-response"),
                "error": Json::string("malformed request"),
              }),
            )
          @lines.InputLine::Line(bytes) =>
            running = parse_dispatch(
              group, mutex, bytes, revision, width, height,
            )
        }
      }
    }
    for line in lines.finish() {
      if !running {
        break
      }
      match line {
        @lines.InputLine::TooLong =>
          send(
            mutex,
            Json::object({
              "id": Json::string("malformed-response"),
              "error": Json::string("malformed request"),
            }),
          )
        @lines.InputLine::Line(bytes) =>
          running = parse_dispatch(group, mutex, bytes, revision, width, height)
      }
    }
  }
}
