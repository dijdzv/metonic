///|
suberror VerifyFailure {
  VerifyFailure(String)
} derive(Debug)

///|
fn fail(message : String) -> Unit raise Error {
  raise VerifyFailure(message)
}

///|
fn field(value : Json, key : String) -> Json? {
  match value {
    Json::Object(values) => values.get(key)
    _ => None
  }
}

///|
fn require(value : Bool, message : String) -> Unit raise Error {
  if !value {
    fail(message)
  }
}

///|
fn bool_field(value : Json, key : String) -> Bool raise Error {
  match field(value, key) {
    Some(Json::True) => true
    Some(Json::False) => false
    _ => {
      fail("missing boolean " + key)
      false
    }
  }
}

///|
fn int_field(value : Json, key : String) -> Int raise Error {
  match field(value, key) {
    Some(Json::Number(n, ..)) if n.to_int().to_double() == n => n.to_int()
    _ => {
      fail("missing integer " + key)
      0
    }
  }
}

///|
fn array_field(value : Json, key : String) -> Array[Json] raise Error {
  match field(value, key) {
    Some(Json::Array(a)) => a
    _ => {
      fail("missing array " + key)
      []
    }
  }
}

///|
fn state(value : Json) -> Array[Json] raise Error {
  let a = array_field(value, "state")
  require(a.length() == 8, "invalid state length")
  a
}

///|
fn si(a : Array[Json], index : Int) -> Int raise Error {
  match a[index] {
    Json::Number(n, ..) if n.to_int().to_double() == n => n.to_int()
    _ => {
      fail("invalid state integer")
      0
    }
  }
}

///|
async fn read_line_inner(
  reader : @process.ReadFromProcess,
  carry : Ref[Array[Byte]],
) -> Json raise Error {
  while true {
    let mut newline : Int? = None
    for i = 0; i < carry.val.length(); i = i + 1 {
      if carry.val[i] == b'\n' {
        newline = Some(i)
        break
      }
    }
    match newline {
      Some(index) => {
        require(index <= 32 * 1024 * 1024, "response line exceeds 32MiB")
        let line : Array[Byte] = []
        for i = 0; i < index; i = i + 1 {
          line.push(carry.val[i])
        }
        let rest : Array[Byte] = []
        for i = index + 1; i < carry.val.length(); i = i + 1 {
          rest.push(carry.val[i])
        }
        carry.val = rest
        let text = @utf8.decode(Bytes::from_array(line)) catch {
          _ => {
            fail("invalid response UTF-8")
            ""
          }
        }
        return @json.parse(text) catch {
          _ => {
            fail("invalid response JSON")
            Json::object({})
          }
        }
      }
      None => ()
    }
    match reader.read_some(max_len=4096) {
      None => {
        fail("unexpected stdout EOF")
        return Json::object({})
      }
      Some(chunk) => {
        for byte in chunk.iter() {
          carry.val.push(byte)
        }
        require(
          carry.val.length() <= 32 * 1024 * 1024,
          "response line exceeds 32MiB",
        )
      }
    }
  } nobreak {
    fail("response unavailable")
    Json::object({})
  }
}

///|
async fn read_line(
  reader : @process.ReadFromProcess,
  carry : Ref[Array[Byte]],
) -> Json raise Error {
  @async.with_timeout(15000, () => read_line_inner(reader, carry))
}

///|
fn request(id : Int, op : String, args : Json) -> String {
  Json::object({
    "id": Json::number(id.to_double()),
    "op": Json::string(op),
    "args": args,
  }).stringify()
}

///|
fn response_of(value : Json) -> Json raise Error {
  require(bool_field(value, "ok"), "host request failed")
  match field(value, "response") {
    Some(response) => response
    _ => {
      fail("response missing")
      Json::object({})
    }
  }
}

///|
fn require_id(value : Json, expected : Int) -> Unit raise Error {
  require(int_field(value, "id") == expected, "response id")
}

///|
fn error_text(value : Json) -> String {
  match field(value, "error") {
    Some(Json::String(s)) => s
    _ => ""
  }
}

///|
fn check_pixels(response : Json, png64 : String) -> Unit raise Error {
  let s = state(response)
  let width = si(s, 6)
  let height = si(s, 7)
  let image = @image.decode_png(@base64.decode(png64))
  require(image.width == width && image.height == height, "PNG dimensions")
  require(image.data.length() == width * height * 4, "PNG data length")
  let x0 = si(s, 0)
  let y0 = si(s, 1)
  let rw = si(s, 2)
  let rh = si(s, 3)
  let fg = [242, 97, 26, 255]
  let bg = [5, 20, 38, 255]
  let mut i = 0
  while i < image.data.length() {
    let p = i / 4
    let x = p % width
    let y = p / width
    let expected = if x >= x0 && x < x0 + rw && y >= y0 && y < y0 + rh {
      fg
    } else {
      bg
    }
    for c in 0..<4 {
      require(
        (image.data[i + c].to_int() - expected[c]).abs() <= 1,
        "PNG pixel mismatch",
      )
    }
    i += 4
  }
}

///|
async fn drain_stderr(
  reader : @process.ReadFromProcess,
  bytes : Ref[Array[Byte]],
) -> Unit raise Error {
  while true {
    match reader.read_some(max_len=4096) {
      None => break
      Some(chunk) => {
        bytes.val.append(chunk.to_array())
        if bytes.val.length() > 65536 {
          fail("stderr exceeds 64KiB")
        }
      }
    }
  }
}

///|
async fn run_case(
  root : String,
  artifact : String,
  fallback : Bool,
  eof : Bool,
) -> Unit raise Error {
  let session = @fs.tmpdir(prefix="native-session-verify-")
  let capture = session + "/capture.rgba"
  let envs : Map[String, String] = Map([])
  envs.set("TEMP", session)
  envs.set("TMP", session)
  if fallback {
    envs.set("METONIC_GPU_FALLBACK", "1")
  }
  defer {
    if @fs.exists(capture) {
      @fs.remove(capture) catch {
        _ => ()
      }
    }
    @fs.rmdir(session) catch {
      _ => ()
    }
  }
  @async.with_timeout(45000, async fn() {
    @async.with_task_group() <| group => {
      let (reader, stdout) = @process.read_from_process()
      let (err_reader, stderr) = @process.read_from_process()
      let (stdin, writer) = @process.write_to_process()
      group.add_defer(fn() {
        reader.close()
        err_reader.close()
        writer.close()
      })
      let process = @process.spawn(
        group,
        @fs.realpath(".tools/moonbit/bin/moonrun.exe"),
        [artifact, "--root", root],
        stdin~,
        stdout~,
        stderr~,
        extra_env=envs,
        no_console_window=true,
        no_wait=true,
        cancel_handler=@process.hard_cancel(),
      )
      group.add_defer(fn() { process.cancel() })
      let err_bytes : Ref[Array[Byte]] = { val: [], }
      group.spawn_bg() <| () => { drain_stderr(err_reader, err_bytes) }
      let carry : Ref[Array[Byte]] = { val: [], }
      let ready = read_line(reader, carry)
      require(int_field(ready, "id") == 0 && bool_field(ready, "ok"), "ready")
      require(field(ready, "session_id") is Some(Json::String(_)), "session_id")
      if eof {
        writer.close()
        require(process.wait() == 0, "ready EOF exit")
      } else {
        writer.write(request(1, "snapshot", Json::object({})))
        writer.write("\n")
        let initial_outer = read_line(reader, carry)
        require_id(initial_outer, 1)
        let initial = response_of(initial_outer)
        let si0 = state(initial)
        require(
          si(si0, 0) == 260 &&
          si(si0, 1) == 144 &&
          si(si0, 2) == 120 &&
          si(si0, 3) == 72 &&
          si(si0, 4) == 0 &&
          si(si0, 5) == 0 &&
          si(si0, 6) == 640 &&
          si(si0, 7) == 360,
          "initial state",
        )
        writer.write(
          request(
            2,
            "move",
            Json::object({
              "x": Json::number(10.0),
              "y": Json::number(20.0),
              "expected_revision": Json::number(0.0),
            }),
          ),
        )
        writer.write("\n")
        let moved_outer = read_line(reader, carry)
        require_id(moved_outer, 2)
        let moved = response_of(moved_outer)
        let sm = state(moved)
        require(si(sm, 0) == 10 && si(sm, 1) == 20 && si(sm, 5) == 1, "move")
        writer.write(
          request(
            3,
            "activate",
            Json::object({ "expected_revision": Json::number(1.0) }),
          ),
        )
        writer.write("\n")
        let active_outer = read_line(reader, carry)
        require_id(active_outer, 3)
        let active = response_of(active_outer)
        let sa = state(active)
        require(si(sa, 4) == 1 && si(sa, 5) == 2, "activate")
        writer.write(
          request(
            4,
            "capture",
            Json::object({ "expected_revision": Json::number(2.0) }),
          ),
        )
        writer.write("\n")
        let captured = read_line(reader, carry)
        require_id(captured, 4)
        let cr = response_of(captured)
        require(int_field(cr, "frame") == 1, "capture frame")
        let image_data = match field(captured, "image") {
          Some(Json::Object(m)) => {
            require(
              m.get("mimeType") == Some(Json::string("image/png")),
              "image MIME",
            )
            match m.get("data") {
              Some(Json::String(v)) => v
              _ => {
                fail("image data")
                ""
              }
            }
          }
          _ => {
            fail("image")
            ""
          }
        }
        check_pixels(cr, image_data)
        let mut found = false
        for entry in @fs.readdir(session) {
          if @fs.exists(session + "/" + entry + "/capture.rgba") {
            found = true
          }
        }
        require(found, "capture file")
        writer.write(
          request(
            5,
            "move",
            Json::object({
              "x": Json::number(0.0),
              "y": Json::number(0.0),
              "expected_revision": Json::number(0.0),
            }),
          ),
        )
        writer.write("\n")
        let stale_outer = read_line(reader, carry)
        require_id(stale_outer, 5)
        require(bool_field(stale_outer, "ok"), "stale transport")
        let stale_response = match field(stale_outer, "response") {
          Some(v) => v
          _ => Json::object({})
        }
        require(!bool_field(stale_response, "ok"), "stale move")
        require(
          error_text(stale_response) == "stale_revision",
          "stale move error",
        )
        let before = state(stale_response)
        writer.write(request(6, "snapshot", Json::object({})))
        writer.write("\n")
        let final_outer = read_line(reader, carry)
        require_id(final_outer, 6)
        let final_response = response_of(final_outer)
        require(state(final_response) == before, "state unchanged")
        writer.close()
      }
      if !eof {
        require(process.wait() == 0, "host exit")
      }
    }
  })
  require(@fs.readdir(session).length() == 0, "session temp cleanup")
  @fs.rmdir(session)
}

///|
async fn main {
  let root = @fs.realpath(".")
  let artifact = root +
    "/_build/wasm/release/build/tools/native_session/native_session.wasm"
  let fallback = @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1")
  let mode = if fallback { "fallback" } else { "default" }
  let result_dir = root + "/.work/native-session"
  if !@fs.exists(result_dir) {
    @fs.mkdir(result_dir, recursive=true)
  }
  let mut failure : String? = None
  run_case(root, artifact, fallback, false) catch {
    error => failure = Some(@debug.to_string(error))
  }
  if failure is None {
    run_case(root, artifact, fallback, true) catch {
      error => failure = Some(@debug.to_string(error))
    }
  }
  let output = match failure {
    Some(error) =>
      Json::object({
        "ok": Json::boolean(false),
        "mode": Json::string(mode),
        "error": Json::string(error),
      })
    None =>
      Json::object({
        "ok": Json::boolean(true),
        "mode": Json::string(mode),
        "checks": Json::array([
          Json::string("ready"),
          Json::string("state"),
          Json::string("capture/png"),
          Json::string("stale"),
          Json::string("eof"),
        ]),
      })
  }
  @fs.write_file(result_dir + "/" + mode + ".json", output.stringify())
  println(output.stringify())
  match failure {
    Some(error) => abort(error)
    None => ()
  }
}
