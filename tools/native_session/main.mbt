///|
suberror SessionError {
  SessionError(String)
} derive(Debug)

///|
fn[T] fail(message : String) -> T raise Error {
  raise SessionError(message)
}

///|
fn field(value : Json, key : String) -> Json? {
  match value {
    Json::Object(values) => values.get(key)
    _ => None
  }
}

///|
fn id_of(value : Json) -> Int raise Error {
  match field(value, "id") {
    Some(Json::Number(number, ..)) if number.to_int().to_double() == number &&
      number >= 1.0 => number.to_int()
    _ => fail("invalid request id")
  }
}

///|
fn op_of(value : Json) -> String raise Error {
  match field(value, "op") {
    Some(Json::String(op)) if op != "" => op
    _ => fail("invalid request op")
  }
}

///|
fn args_of(value : Json) -> Json raise Error {
  match field(value, "args") {
    None => Json::object({})
    Some(args) =>
      match args {
        Json::Object(_) => args
        _ => fail("args must be an object")
      }
  }
}

///|
fn json_int(value : Json) -> Int raise Error {
  match value {
    Json::Number(number, ..) if number.to_int().to_double() == number =>
      number.to_int()
    _ => fail("invalid integer")
  }
}

///|
fn expected_revision(value : Json) -> Int? raise Error {
  match field(value, "expected_revision") {
    None => None
    Some(Json::Number(number, ..)) if number.to_int().to_double() == number &&
      number >= 0.0 => Some(number.to_int())
    _ => fail("expected_revision must be a non-negative integer")
  }
}

///|
fn output(value : Json) -> String {
  value.stringify() + "\n"
}

///|
async fn write(mutex : @async.Mutex, value : Json) -> Unit {
  mutex.acquire()
  defer mutex.release()
  @stdio.stdout.write(output(value))
}

///|
async fn handle(
  client : @control.Client,
  mutex : @async.Mutex,
  pending : Ref[Int],
  value : Json,
) -> Unit {
  defer {
    pending.val = pending.val - 1
  }
  let id = id_of(value) catch {
    error =>
      return write(
        mutex,
        Json::object({
          "id": Json::number(0.0),
          "ok": Json::boolean(false),
          "error": Json::string(@debug.to_string(error)),
        }),
      )
  }
  let op = op_of(value) catch {
    error =>
      return write(
        mutex,
        Json::object({
          "id": Json::number(id.to_double()),
          "ok": Json::boolean(false),
          "error": Json::string(@debug.to_string(error)),
        }),
      )
  }
  if op == "shutdown" {
    return write(
      mutex,
      Json::object({
        "id": Json::number(id.to_double()),
        "ok": Json::boolean(false),
        "error": Json::string("shutdown is host-owned"),
      }),
    )
  }
  let args = args_of(value) catch {
    error =>
      return write(
        mutex,
        Json::object({
          "id": Json::number(id.to_double()),
          "ok": Json::boolean(false),
          "error": Json::string(@debug.to_string(error)),
        }),
      )
  }
  let response_json = try {
    if op == "capture" {
      let captured = client.capture(expected_revision=expected_revision(args))
      let values = match field(captured.0, "state") {
        Some(Json::Array(values)) => values
        _ => fail("capture state missing")
      }
      let png = @image.encode_png(@image.ImageData::{
        width: json_int(values[6]),
        height: json_int(values[7]),
        data: captured.1,
      })
      Json::object({
        "id": Json::number(id.to_double()),
        "ok": Json::boolean(true),
        "response": captured.0,
        "image": Json::object({
          "mimeType": Json::string("image/png"),
          "data": Json::string(@base64.encode(png)),
        }),
      })
    } else {
      let response = client.request(op, args~)
      Json::object({
        "id": Json::number(id.to_double()),
        "ok": Json::boolean(true),
        "response": response,
      })
    }
  } catch {
    error => {
      if @async.is_cancellation_error(error) {
        raise error
      }
      Json::object({
        "id": Json::number(id.to_double()),
        "ok": Json::boolean(false),
        "error": Json::string(@debug.to_string(error)),
      })
    }
  }
  write(mutex, response_json)
}

///|
async fn main {
  let args = @env.args()
  let mut root = @fs.realpath(".")
  let mut index = 1
  while index < args.length() {
    if args[index] == "--root" && index + 1 < args.length() {
      root = @fs.realpath(args[index + 1])
      index += 2
    } else {
      abort("--root PATH is required")
    }
  }
  let session = @fs.tmpdir(prefix="native-session-")
  let capture = session + "/capture.rgba"
  defer @async.protect_from_cancel() <| () => {
    if @fs.exists(capture) {
      @fs.remove(capture) catch {
        error =>
          @stdio.stderr.write(
            "capture cleanup failed: " + @debug.to_string(error) + "\n",
          )
      }
    }
    @fs.rmdir(session) catch {
      error =>
        @stdio.stderr.write(
          "session cleanup failed: " + @debug.to_string(error) + "\n",
        )
    }
  }
  let config = @control.Config::new(
    root +
    "/_build/native/release/build/examples/p0/native_headless/native_headless.exe",
    [],
    capture,
    15000,
    16,
  )
  @control.with_client(config, async fn(client) {
    @async.with_task_group() <| group => {
      let mutex = @async.Mutex::Mutex()
      let pending : Ref[Int] = { val: 0, }
      let active : Map[Int, @async.Task[Unit]] = Map([])
      let mut last_id = 0
      let session_parts = session
        .replace_all(old="\\", new="/")
        .split("/")
        .to_array()
      let session_id = session_parts[session_parts.length() - 1].to_owned()
      write(
        mutex,
        Json::object({
          "id": Json::number(0.0),
          "ok": Json::boolean(true),
          "session_id": Json::string(session_id),
        }),
      )
      let lines = @lines.Lines::new()
      while @stdio.stdin.read_some(max_len=4096) is Some(chunk) {
        for line in lines.feed(chunk) {
          match line {
            @lines.InputLine::TooLong => fail("input line exceeds 4095 bytes")
            @lines.InputLine::Line(bytes) => {
              let parsed = @json.parse(@utf8.decode(bytes)) catch {
                _ => fail("invalid request")
              }
              let id = id_of(parsed) catch {
                error => fail(@debug.to_string(error))
              }
              for old_id, task in active {
                match task.try_wait() {
                  Some(_) => active.remove(old_id)
                  None => ()
                }
              }
              if id <= last_id {
                fail("duplicate or out-of-order request id")
              }
              if active.length() >= 16 {
                fail("too many pending requests")
              }
              last_id = id
              pending.val = pending.val + 1
              let task = group.spawn(() => {
                handle(client, mutex, pending, parsed)
              })
              active.set(id, task)
            }
          }
        }
      }
      for line in lines.finish() {
        match line {
          @lines.InputLine::TooLong => fail("input line exceeds 4095 bytes")
          @lines.InputLine::Line(bytes) => {
            let parsed = @json.parse(@utf8.decode(bytes)) catch {
              _ => fail("invalid request")
            }
            let id = id_of(parsed) catch {
              error => fail(@debug.to_string(error))
            }
            for old_id, task in active {
              match task.try_wait() {
                Some(_) => active.remove(old_id)
                None => ()
              }
            }
            if id <= last_id || active.length() >= 16 {
              fail("duplicate or too many requests")
            }
            last_id = id
            pending.val = pending.val + 1
            let task = group.spawn(() => handle(client, mutex, pending, parsed))
            active.set(id, task)
          }
        }
      }
      for _, task in active {
        task.cancel()
      }
      for _, task in active {
        task.wait() catch {
          error => if !@async.is_cancellation_error(error) { raise error }
        }
      }
      client.close()
    }
  })
}
