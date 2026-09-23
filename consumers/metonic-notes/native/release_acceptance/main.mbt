///|
extern "C" fn find_next(
  parent : UInt64,
  after : UInt64,
  class_name : UInt64,
  title : UInt64,
) -> UInt64 = "FindWindowExW"

///|
#borrow(pid)
extern "C" fn owner(window : UInt64, pid : FixedArray[Int]) -> UInt = "GetWindowThreadProcessId"

///|
extern "C" fn post(
  window : UInt64,
  message : UInt,
  key : UInt64,
  data : Int64,
) -> Int = "PostMessageW"

///|
#borrow(rect)
extern "C" fn client_rect(window : UInt64, rect : FixedArray[Int]) -> Int = "GetClientRect"

///|
#borrow(buffer)
extern "C" fn title(
  window : UInt64,
  buffer : FixedArray[Byte],
  capacity : Int,
) -> Int = "GetWindowTextW"

///|
fn locate(pid : Int) -> UInt64 raise {
  let id = FixedArray::make(1, 0)
  let mut cursor = 0UL
  for _ in 0..<4096 {
    cursor = find_next(0UL, cursor, 0UL, 0UL)
    if cursor == 0UL {
      return 0UL
    }
    if owner(cursor, id) != 0U && id[0] == pid {
      let rect = FixedArray::make(4, 0)
      let buffer = FixedArray::make(10, b'\x00')
      let expected : FixedArray[Byte] = [77, 0, 101, 0, 109, 0, 111, 0, 0, 0]
      if title(cursor, buffer, 5) == 4 &&
        buffer == expected &&
        client_rect(cursor, rect) != 0 &&
        rect[2] == 760 &&
        rect[3] == 520 {
        return cursor
      }
    }
  }
  fail("Owned application window was not found")
}

///|
fn send(
  window : UInt64,
  message : UInt,
  key : UInt64,
  data : Int64,
) -> Unit raise {
  assert_true(post(window, message, key, data) != 0)
}

///|
async fn click(window : UInt64, x : Int, y : Int) -> Unit {
  let point = (y * 65536 + x).to_int64()
  send(window, 0x0201U, 1UL, point)
  send(window, 0x0202U, 0UL, point)
  @async.sleep(150)
}

///|
async fn type_text(window : UInt64, text : String) -> Unit {
  for index in 0..<text.length() {
    let unit = text[index].to_int()
    if unit == 10 {
      send(window, 0x0100U, 13UL, 0L)
      send(window, 0x0101U, 13UL, 0L)
    } else {
      send(window, 0x0102U, unit.to_uint64(), 0L)
    }
  }
  @async.sleep(150)
}

///|
async fn select_editor_by_drag(window : UInt64, backward : Bool) -> Unit {
  let start = 174L * 65536L + 260L
  let end = 430L * 65536L + 735L
  let down = if backward { end } else { start }
  let up = if backward { start } else { end }
  send(window, 0x0201U, 1UL, down)
  send(window, 0x0200U, 1UL, up)
  send(window, 0x0202U, 0UL, up)
  @async.sleep(150)
}

///|
async fn expect_snapshot(path : String, expected : String) -> Unit {
  for _ in 0..<100 {
    if @fs.exists(path) {
      let document = @collection.decode(Some(@fs.read_file(path).text())).unwrap()
      if document.items().length() == 1 && document.items()[0].text == expected {
        return
      }
    }
    @async.sleep(50)
  }
  let actual = if @fs.exists(path) {
    @fs.read_file(path).text()
  } else {
    "<snapshot missing>"
  }
  fail(
    "Release application did not save expected text: " +
    expected +
    "; actual=" +
    actual,
  )
}

///|
async fn main {
  let args = @env.args()
  if args.length() == 3 && args[1] == "--close-owned-window" {
    let pid = @string.parse_int(args[2])
    assert_true(pid > 0)
    let window = locate(pid)
    assert_true(window != 0UL)
    send(window, 0x0010U, 0UL, 0L)
    return
  }
  assert_eq(args.length(), 2)
  let executable = @fs.realpath(args[1])
  let previous_font = @env.get_env_var("METONIC_FONT_PATH")
  @env.unset_env_var("METONIC_FONT_PATH")
  defer (match previous_font {
    Some(path) => @env.set_env_var("METONIC_FONT_PATH", path)
    None => ()
  })
  let temporary = @fs.tmpdir(prefix="metonic-release-acceptance-")
  let resolved = @fs.realpath(temporary)
  defer {
    assert_eq(@fs.realpath(temporary), resolved)
    @fs.rmdir(temporary, recursive=true)
  }
  for restored in [false, true] {
    @async.with_timeout(20000, async fn() {
      @async.with_task_group() <| group => {
        let child = @process.spawn(
          group,
          executable,
          [],
          cwd=temporary,
          extra_env=Map([("METONIC_NOTES_DATA", temporary + "/data")]),
          no_console_window=true,
          cancel_handler=@process.hard_cancel(),
        )
        let mut window = 0UL
        while window == 0UL {
          assert_true(
            child.try_wait() == None,
            msg="Application exited during startup",
          )
          window = locate(child.pid)
          @async.sleep(50)
        }
        @async.sleep(1000)
        if restored {
          click(window, 280, 200)
          type_text(window, "再")
        } else {
          click(window, 80, 75)
          type_text(window, "削除するメモ")
          click(window, 80, 75)
          type_text(window, "配布メモ\n復元確認")
          click(window, 90, 185)
          click(window, 300, 75)
          click(window, 300, 75)
          select_editor_by_drag(window, false)
          type_text(window, "ドラッグ保存\n復元確認")
          click(window, 80, 40)
          expect_snapshot(temporary + "/data/snapshot", "ドラッグ保存\n復元確認")
          select_editor_by_drag(window, true)
          type_text(window, "配布メモ\n復元確認")
        }
        click(window, 80, 40)
        let snapshot = temporary + "/data/snapshot"
        if restored {
          // Replacing the store with a second new note would not prove restoration.
          for _ in 0..<100 {
            let document = @collection.decode(
              Some(@fs.read_file(snapshot).text()),
            ).unwrap()
            if document.items().length() == 1 &&
              document.items()[0].text.contains("再") {
              assert_eq(
                document.items()[0].text.replace(old="再", new=""),
                "配布メモ\n復元確認",
              )
              break
            }
            @async.sleep(50)
          } nobreak {
            fail("Restored editor did not preserve the saved note")
          }
        } else {
          expect_snapshot(snapshot, "配布メモ\n復元確認")
        }
        send(window, 0x0010U, 0UL, 0L)
        assert_eq(child.wait(), 0)
      }
    })
  }
  println(
    "NATIVE_RELEASE_EDIT_SAVE_RESTORE_OK create_select_delete_confirm forward_backward_drag_replace owned_window_messages not_physical_IME",
  )
}
