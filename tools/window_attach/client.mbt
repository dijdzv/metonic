///|
pub suberror AttachError {
  Failure(String)
} derive(Debug)

///|
pub struct Discovery {
  protocol_version : Int
  session_id : String
  pipe : String
} derive(FromJson)

///|
fn fail(message : String) -> Unit raise AttachError {
  raise Failure(message)
}

///|
fn valid_name(name : String, limit : Int) -> Bool {
  name.length() > 0 &&
  name.length() <= limit &&
  name
  .to_array()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '.' ||
    c == '-' ||
    c == '_'
  })
}

///|
pub fn parse_discovery(text : String) -> Discovery raise {
  if @utf8.encode(text).length() > 4096 {
    fail("discovery exceeds 4 KiB")
  }
  let result : Discovery = @json.from_json(@json.parse(text))
  guard result.pipe.strip_prefix("\\\\.\\pipe\\") is Some(name) &&
    valid_name(name.to_owned(), 128) &&
    valid_name(result.session_id, 256) &&
    result.protocol_version == 1 else {
    fail("unsupported or invalid discovery")
    abort("unreachable")
  }
  result
}

///|
pub struct Client {
  priv file : @fs.File
  priv discovery : Discovery
  priv mut next_id : Int
  priv mut busy : Bool
  priv mut closed : Bool
}

///|
pub fn Client::close(self : Client) -> Unit {
  if !self.closed {
    self.closed = true
    self.file.close()
  }
}

///|
async fn response_line(file : @fs.File) -> String {
  let bytes : Array[Byte] = []
  while file.read_some(max_len=4096) is Some(chunk) {
    for i in 0..<chunk.length() {
      if chunk[i] == b'\n' {
        if i != chunk.length() - 1 {
          fail("unsolicited trailing response")
        }
        return @utf8.decode(Bytes::from_array(bytes))
      }
      if bytes.length() >= 32 * 1024 * 1024 {
        fail("response exceeds 32 MiB")
      }
      bytes.push(chunk[i])
    }
  }
  fail("connection closed before response")
  abort("unreachable")
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Json::Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
pub async fn Client::request(
  self : Client,
  op : String,
  args : Json,
  timeout_ms? : Int = 5000,
) -> Json {
  if self.closed || self.busy {
    fail("connection closed or busy")
  }
  if timeout_ms < 1 || timeout_ms > 60000 {
    fail("invalid timeout")
  }
  guard args is Json::Object(args) else {
    fail("arguments must be an object")
    abort("unreachable")
  }
  let fields : Map[String, Json] = Map([])
  for key, value in args {
    if key == "id" || key == "op" || key == "session_id" {
      fail("reserved request field")
    }
    fields[key] = value
  }
  if self.next_id == 2147483647 {
    fail("request IDs exhausted")
  }
  let id = self.next_id
  self.next_id += 1
  fields["id"] = Json::number(id.to_double())
  fields["op"] = Json::string(op)
  fields["session_id"] = Json::string(self.discovery.session_id)
  let encoded = @utf8.encode(Json::object(fields).stringify() + "\n")
  if encoded.length() > 65536 {
    fail("request exceeds 64 KiB")
  }
  self.busy = true
  defer {
    self.busy = false
  }
  errdefer self.close()
  @async.with_timeout(timeout_ms, () => {
    self.file.write(encoded)
    let text = response_line(self.file)
    let problem = @wire.validate_response(text, true, false)
    if problem != "" {
      fail(problem)
    }
    let response = @json.parse(text)
    if field(response, "id") != Json::number(id.to_double()) ||
      field(response, "session_id") != Json::string(self.discovery.session_id) ||
      field(response, "protocol_version") != Json::number(1) {
      fail("response identity mismatch")
    }
    response
  })
}

///|
pub async fn connect(
  discovery_path : String,
  timeout_ms? : Int = 5000,
) -> Client {
  if timeout_ms < 1 || timeout_ms > 60000 {
    fail("invalid timeout")
  }
  @async.with_timeout(timeout_ms, () => {
    let input = @fs.open(discovery_path, mode=ReadOnly)
    defer input.close()
    let bytes : Array[Byte] = []
    while input.read_some(max_len=4096) is Some(chunk) {
      if bytes.length() + chunk.length() > 4096 {
        fail("discovery exceeds 4 KiB")
      }
      for byte in chunk {
        bytes.push(byte)
      }
    }
    let discovery = parse_discovery(@utf8.decode(Bytes::from_array(bytes)))
    let file = @fs.open(discovery.pipe, mode=ReadWrite)
    let client = Client::{
      file,
      discovery,
      next_id: 1,
      busy: false,
      closed: false,
    }
    errdefer client.close()
    let ready = client.request("capabilities", Json::object({}), timeout_ms~)
    if field(ready, "error") != Json::string("") {
      fail("capabilities rejected")
    }
    client
  })
}
