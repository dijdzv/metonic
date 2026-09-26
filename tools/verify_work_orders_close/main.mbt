///|
extern "C" fn next_window(
  parent : UInt64,
  after : UInt64,
  class_name : UInt64,
  title : UInt64,
) -> UInt64 = "FindWindowExW"

///|
#borrow(pid)
extern "C" fn window_pid(hwnd : UInt64, pid : FixedArray[Int]) -> UInt = "GetWindowThreadProcessId"

///|
extern "C" fn title_length(hwnd : UInt64) -> Int = "GetWindowTextLengthW"

///|
#borrow(text)
extern "C" fn window_title(
  hwnd : UInt64,
  text : FixedArray[Byte],
  capacity : Int,
) -> Int = "GetWindowTextW"

///|
extern "C" fn post_close(
  hwnd : UInt64,
  message : UInt,
  wparam : UInt64,
  lparam : Int64,
) -> Int = "PostMessageW"

///|
fn field(value : Json, name : String) -> Json {
  guard value is Json::Object(fields) else { abort("Expected object") }
  fields.get(name).unwrap_or(Json::null())
}

///|
fn control(response : Json, name : String) -> Json? {
  guard field(response, "controls") is Json::Array(controls) else {
    return None
  }
  controls.iter().find_first(item => field(item, "name") == Json::string(name))
}

///|
async fn request(
  writer : @process.WriteToProcess,
  reader : @process.ReadFromProcess,
  message : Json,
) -> Json {
  writer.write(message.stringify() + "\n")
  let response = @json.parse(reader.read_until("\n").unwrap())
  assert_eq(field(response, "error"), Json::string(""))
  response
}

///|
fn owned_window(pid : Int) -> UInt64 {
  let owner = FixedArray::make(1, 0)
  let name = "Work orders"
  let encoded = @utf16.encode(name, bom=false, endianness=Little)
  let expected : FixedArray[Byte] = FixedArray::makei(encoded.length() + 2, index => {
    if index < encoded.length() {
      encoded[index]
    } else {
      0
    }
  })
  let title = FixedArray::make(expected.length(), b'\x00')
  let mut cursor = 0UL
  let mut found = 0UL
  for _ in 0..<4096 {
    cursor = next_window(0UL, cursor, 0UL, 0UL)
    if cursor == 0UL {
      return found
    }
    if window_pid(cursor, owner) != 0U &&
      owner[0] == pid &&
      title_length(cursor) == name.length() &&
      window_title(cursor, title, name.length() + 1) == name.length() &&
      title == expected {
      if found != 0UL {
        abort("More than one owned titled window")
      }
      found = cursor
    }
  }
  abort("Owned window enumeration exceeded bound")
}

///|
async fn wait_close_prompt(
  writer : @process.WriteToProcess,
  reader : @process.ReadFromProcess,
  id : Ref[Int],
) -> Json {
  for _ in 0..<100 {
    let response = request(writer, reader, { "id": id.val, "op": "snapshot" })
    id.val += 1
    if control(response, "Discard") is Some(button) &&
      field(button, "enabled") == Json::boolean(true) {
      assert_true(
        control(response, "Close requested | Unsaved changes") is Some(_),
      )
      return response
    }
    @async.sleep(50)
  }
  abort("Unsaved close prompt did not appear")
}

///|
async fn run_case(
  executable : String,
  directory : String,
  discard : Bool,
) -> Unit {
  @async.with_timeout(30000, () => {
    @async.with_task_group() <| group => {
      let (input, writer) = @process.write_to_process()
      defer writer.close()
      let (reader, output) = @process.read_from_process()
      defer reader.close()
      let child = @process.spawn(
        group,
        executable,
        [],
        stdin=input,
        stdout=output,
        extra_env=Map([("METONIC_WORK_ORDERS_DATA", directory)]),
        no_console_window=true,
        cancel_handler=@process.hard_cancel(),
      )
      let id : Ref[Int] = Ref(1)
      let mut initial = request(writer, reader, {
        "id": id.val,
        "op": "snapshot",
      })
      id.val += 1
      for _ in 0..<100 {
        if control(initial, "Title") is Some(title) &&
          field(title, "enabled") == Json::boolean(true) {
          break
        }
        @async.sleep(50)
        initial = request(writer, reader, { "id": id.val, "op": "snapshot" })
        id.val += 1
      }
      assert_true(control(initial, "Title") is Some(_))
      let mut hwnd = 0UL
      for _ in 0..<100 {
        hwnd = owned_window(child.pid)
        if hwnd != 0UL {
          break
        }
        @async.sleep(50)
      }
      assert_true(hwnd != 0UL, msg="Owned window was not created")
      assert_true(post_close(hwnd, 0x0010U, 0UL, 0L) != 0)
      let mut prompt = wait_close_prompt(writer, reader, id)
      if discard {
        let cancel = control(prompt, "Keep editing").unwrap()
        let resumed = request(writer, reader, {
          "id": id.val,
          "op": "activate",
          "target": field(cancel, "target"),
          "expected_semantic_revision": field(prompt, "semantic_revision"),
        })
        id.val += 1
        assert_eq(
          field(control(resumed, "Title").unwrap(), "enabled"),
          Json::boolean(true),
        )
        assert_eq(
          field(control(resumed, "Discard").unwrap(), "enabled"),
          Json::boolean(false),
        )
        assert_true(post_close(hwnd, 0x0010U, 0UL, 0L) != 0)
        prompt = wait_close_prompt(writer, reader, id)
      }
      let action = control(prompt, if discard { "Discard" } else { "Save" }).unwrap()
      writer.write(
        Json::object({
          "id": Json::number(id.val.to_double()),
          "op": Json::string("activate"),
          "target": field(action, "target"),
          "expected_semantic_revision": field(prompt, "semantic_revision"),
        }).stringify() +
        "\n",
      )
      assert_eq(child.wait(), 0)
      assert_eq(@fs.exists(directory + "/snapshot"), !discard)
    }
  })
}

///|
async fn main {
  let root = @fs.realpath(".")
  let executable = root +
    "/consumers/metonic-work-orders/native/.metonic-build/native/debug/build/local/metonic_work_orders_native/dev/dev.exe"
  assert_true(@fs.exists(executable), msg="Build Work orders dev entry first")
  let session = @fs.tmpdir(prefix="metonic-work-orders-close-")
  let directory = session + "/data"
  run_case(executable, directory, true)
  run_case(executable, directory, false)
  @fs.remove(directory + "/snapshot")
  @fs.remove(directory + "/writer.lock")
  @fs.rmdir(directory)
  @fs.rmdir(session)
  println("WORK_ORDERS_CLOSE_OK cancel discard save")
}
