///|
suberror CLIError {
  CLIError(String)
} derive(Debug)

///|
fn field(object : Json, key : String) -> Json? {
  match object {
    Json::Object(values) => values.get(key)
    _ => None
  }
}

///|
fn error_line(message : String) -> String {
  Json::object({ "ok": Json::boolean(false), "error": Json::string(message) }).stringify() +
  "\n"
}

///|
fn args_or_empty(request : Json) -> Json raise Error {
  match field(request, "args") {
    None => Json::object({})
    Some(args) =>
      match args {
        Json::Object(_) => args
        _ => raise CLIError("args must be an object")
      }
  }
}

///|
fn expected_revision(args : Json) -> Int? raise Error {
  match field(args, "expected_revision") {
    None => None
    Some(Json::Number(value, ..)) => {
      let revision = value.to_int()
      if revision < 0 || revision.to_double() != value {
        raise CLIError("expected_revision must be a non-negative integer")
      }
      Some(revision)
    }
    _ => raise CLIError("expected_revision must be an integer")
  }
}

///|
async fn write_line(text : String) -> Unit {
  @stdio.stdout.write(text)
}

///|
async fn process_line(client : @control.Client, raw : Bytes) -> Unit {
  let text = @utf8.decode(raw) catch {
    _ => return write_line(error_line("invalid UTF-8 input"))
  }
  let request = @json.parse(text) catch {
    _ => return write_line(error_line("invalid JSON input"))
  }
  let output = try {
    let op = match field(request, "op") {
      Some(Json::String(value)) => value
      _ => raise CLIError("op must be a string")
    }
    let args = args_or_empty(request)
    if op == "capture" {
      let captured = client.capture(expected_revision=expected_revision(args))
      let image = @image.ImageData::{
        width: match field(captured.0, "state") {
          Some(Json::Array(values)) =>
            match values[6] {
              Json::Number(value, ..) => value.to_int()
              _ => 0
            }
          _ => 0
        },
        height: match field(captured.0, "state") {
          Some(Json::Array(values)) =>
            match values[7] {
              Json::Number(value, ..) => value.to_int()
              _ => 0
            }
          _ => 0
        },
        data: captured.1,
      }
      let response = Json::object({
        "response": captured.0,
        "image": Json::object({
          "mimeType": Json::string("image/png"),
          "data": Json::string(@base64.encode(@image.encode_png(image))),
        }),
      })
      response.stringify() + "\n"
    } else {
      client.request(op, args~).stringify() + "\n"
    }
  } catch {
    error => {
      if @async.is_cancellation_error(error) {
        raise error
      }
      error_line(@debug.to_string(error))
    }
  }
  write_line(output)
}

///|
async fn main {
  let cli_args = @env.args()
  let root = try {
    let mut value = @fs.realpath(".")
    let mut i = 1
    while i < cli_args.length() {
      if cli_args[i] == "--root" {
        if i + 1 >= cli_args.length() {
          raise CLIError("missing value for --root")
        }
        value = @fs.realpath(cli_args[i + 1])
        i += 2
      } else {
        raise CLIError("unknown option: " + cli_args[i])
      }
    }
    value
  } catch {
    error => {
      @stdio.stderr.write(@debug.to_string(error) + "\n")
      abort(@debug.to_string(error))
    }
  }
  let session = @fs.tmpdir(prefix="native-cli-")
  let capture = session + "/capture.rgba"
  defer @async.protect_from_cancel() <| () => {
    if @fs.exists(capture) {
      @fs.remove(capture) catch {
        error =>
          @stdio.stderr.write(@debug.to_string(error) + "\n") catch {
            _ => ()
          }
      }
    }
    @fs.rmdir(session) catch {
      error =>
        @stdio.stderr.write(@debug.to_string(error) + "\n") catch {
          _ => ()
        }
    }
  }
  let config = @control.Config::new(
    root +
    "/_build/native/release/build/examples/p0/native_headless/native_headless.exe",
    [],
    root + "/.work/native-cargo/release/metonic_wgpu_probe.dll",
    capture,
    15000,
    16,
  )
  @control.with_client(config, async fn(client) {
    let lines = @lines.Lines::new()
    while @stdio.stdin.read_some(max_len=4096) is Some(chunk) {
      for line in lines.feed(chunk) {
        match line {
          @lines.InputLine::TooLong =>
            write_line(error_line("input line exceeds 4095 bytes"))
          @lines.InputLine::Line(bytes) => process_line(client, bytes)
        }
      }
    }
    for line in lines.finish() {
      match line {
        @lines.InputLine::TooLong =>
          write_line(error_line("input line exceeds 4095 bytes"))
        @lines.InputLine::Line(bytes) => process_line(client, bytes)
      }
    }
    client.close()
  })
}
