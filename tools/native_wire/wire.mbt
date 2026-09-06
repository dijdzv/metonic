///|
priv suberror WireFailure {
  WireFailure(String)
} derive(Debug)

///|
fn[T] wire_fail(message : String) -> T raise WireFailure {
  raise WireFailure(message)
}

///|
fn valid_int(value : Double, low : Int, high : Int) -> Bool {
  value.to_int().to_double() == value &&
  value >= low.to_double() &&
  value <= high.to_double()
}

///|
pub struct WireLines {
  mut pending : Array[Byte]
}

///|
pub fn WireLines::new() -> WireLines {
  { pending: [], }
}

///|
pub fn wire_request(
  id : Int,
  op : String,
  args : Json,
  internal_capture : Bool,
) -> String raise Error {
  if id < 1 ||
    id > 2147483647 ||
    op == "" ||
    (!internal_capture && op == "capture") {
    wire_fail("invalid request")
  }
  let object : Map[String, Json] = Map([])
  object.set("version", Json::number(1.0))
  object.set("id", Json::number(id.to_double()))
  object.set("op", Json::string(op))
  match args {
    Json::Object(fields) =>
      for key, value in fields {
        if key == "version" || key == "id" || key == "op" {
          wire_fail("reserved request field")
        }
        object.set(key, value)
      }
    _ => wire_fail("args must be object")
  }
  let body = Json::object(object).stringify()
  if @utf8.encode(body).length() > 4095 {
    wire_fail("request exceeds 4095 bytes")
  }
  body
}

///|
pub fn wire_response(line : Bytes) -> (Int, Json) raise Error {
  if line.length() > 65536 {
    wire_fail("response line exceeds 64KiB")
  }
  let object = @json.parse(@utf8.decode(line))
  match object {
    Json::Object(fields) => {
      let id = match fields.get("id") {
        Some(Json::Number(value, ..)) if valid_int(value, 1, 2147483647) =>
          value.to_int()
        _ => wire_fail("invalid response id")
      }
      match fields.get("version") {
        Some(Json::Number(value, ..)) if valid_int(value, 1, 1) => ()
        _ => wire_fail("invalid response version")
      }
      match fields.get("ok") {
        Some(Json::True) => ()
        Some(Json::False) =>
          match fields.get("error") {
            Some(Json::String(_)) => ()
            _ => wire_fail("invalid response error")
          }
        _ => wire_fail("invalid response ok")
      }
      let values = match fields.get("state") {
        Some(Json::Array(values)) if values.length() == 8 => values
        _ => wire_fail("invalid response state")
      }
      for value in values {
        match value {
          Json::Number(number, ..) if valid_int(number, -2147483648, 2147483647) =>
            ()
          _ => wire_fail("invalid state value")
        }
      }
      for index in [6, 7] {
        match values[index] {
          Json::Number(value, ..) if valid_int(value, 1, 2048) => ()
          _ => wire_fail("invalid viewport")
        }
      }
      match fields.get("frame") {
        Some(Json::Number(value, ..)) if valid_int(value, 0, 2147483647) => ()
        _ => wire_fail("invalid frame")
      }
      (id, object)
    }
    _ => wire_fail("response must be object")
  }
}

///|
fn copy_bytes(values : Array[Byte], start : Int, end : Int) -> Bytes {
  let result : Array[Byte] = []
  let mut index = start
  while index < end {
    result.push(values[index])
    index = index + 1
  }
  Bytes::from_array(result)
}

///|
pub fn WireLines::feed(
  self : WireLines,
  chunk : Bytes,
) -> Array[Bytes] raise Error {
  let output : Array[Bytes] = []
  for byte in chunk.iter() {
    if byte == b'\n' {
      let end = if self.pending.length() > 0 &&
        self.pending[self.pending.length() - 1] == b'\r' {
        self.pending.length() - 1
      } else {
        self.pending.length()
      }
      output.push(copy_bytes(self.pending, 0, end))
      self.pending = []
    } else {
      self.pending.push(byte)
      if self.pending.length() > 65536 {
        wire_fail("wire line exceeds 64KiB")
      }
    }
  }
  output
}

///|
pub fn WireLines::finish(self : WireLines) -> Unit raise Error {
  if self.pending.length() != 0 {
    wire_fail("truncated wire line")
  }
}
