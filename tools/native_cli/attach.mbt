///|
async fn attached_line(
  client : @attach.Client,
  bytes : Bytes,
  wire : Bool,
) -> Unit {
  if wire {
    let request = @json.parse(@utf8.decode(bytes))
    guard request is Json::Object(fields) &&
      fields.get("id") is Some(Json::Number(id, ..)) &&
      id >= 1 &&
      id <= 2147483647 &&
      id.to_int().to_double() == id &&
      fields.get("op") is Some(Json::String(op)) else {
      raise CLIError("invalid attachment bridge request")
    }
    let args : Map[String, Json] = Map([])
    for key, value in fields {
      if key != "id" && key != "op" {
        args.set(key, value)
      }
    }
    let response = client.request(op, Json::object(args))
    guard response is Json::Object(result) else {
      raise CLIError("invalid attachment bridge response")
    }
    result.set("id", Json::number(id))
    write_line(Json::object(result).stringify() + "\n")
    return
  }
  let output = try {
    let request = @json.parse(@utf8.decode(bytes))
    guard field(request, "op") is Some(Json::String(op)) else {
      raise CLIError("op must be a string")
    }
    client.request(op, args_or_empty(request)).stringify() + "\n"
  } catch {
    error if @async.is_cancellation_error(error) => raise error
    error => error_line(@debug.to_string(error))
  }
  write_line(output)
}

///|
async fn run_attached(path : String, wire? : Bool = false) -> Unit {
  let client = @attach.connect(path)
  defer client.close()
  let lines = @lines.Lines::new()
  while @stdio.stdin.read_some(max_len=4096) is Some(chunk) {
    for line in lines.feed(chunk) {
      match line {
        @lines.InputLine::TooLong =>
          if wire {
            raise CLIError("input line exceeds 4095 bytes")
          } else {
            write_line(error_line("input line exceeds 4095 bytes"))
          }
        @lines.InputLine::Line(bytes) => attached_line(client, bytes, wire)
      }
    }
  }
  for line in lines.finish() {
    match line {
      @lines.InputLine::TooLong =>
        if wire {
          raise CLIError("input line exceeds 4095 bytes")
        } else {
          write_line(error_line("input line exceeds 4095 bytes"))
        }
      @lines.InputLine::Line(bytes) => attached_line(client, bytes, wire)
    }
  }
}
