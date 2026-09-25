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
#borrow(buffer)
extern "C" fn title(
  window : UInt64,
  buffer : FixedArray[Byte],
  capacity : Int,
) -> Int = "GetWindowTextW"

///|
#borrow(rect)
extern "C" fn client_rect(window : UInt64, rect : FixedArray[Int]) -> Int = "GetClientRect"

///|
extern "C" fn post(
  window : UInt64,
  message : UInt,
  key : UInt64,
  data : Int64,
) -> Int = "PostMessageW"

///|
fn locate(pid : Int) -> UInt64 {
  let id = FixedArray::make(1, 0)
  let mut cursor = 0UL
  for _ in 0..<4096 {
    cursor = find_next(0UL, cursor, 0UL, 0UL)
    if cursor == 0UL {
      return 0UL
    }
    if owner(cursor, id) != 0U && id[0] == pid {
      let buffer = FixedArray::make(128, b'\x00')
      let rect = FixedArray::make(4, 0)
      if title(cursor, buffer, 64) > 0 &&
        client_rect(cursor, rect) != 0 &&
        rect[2] >= 700 &&
        rect[3] >= 480 {
        return cursor
      }
    }
  }
  0UL
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
async fn main {
  let args = @env.args()
  assert_eq(args.length(), 2, msg="usage: release_probe.exe <QuoteBoard.exe>")
  let executable = @fs.realpath(args[1])
  let temporary = @fs.tmpdir(prefix="metonic-quote-package-")
  let resolved = @fs.realpath(temporary)
  defer {
    assert_eq(@fs.realpath(temporary), resolved)
    @fs.rmdir(temporary, recursive=true)
  }
  @async.with_timeout(20000, async fn() {
    @async.with_task_group() <| group => {
      let child = @process.spawn(
        group,
        executable,
        [],
        cwd=temporary,
        no_console_window=true,
        cancel_handler=@process.hard_cancel(),
      )
      let mut window = 0UL
      while window == 0UL {
        assert_true(
          child.try_wait() == None,
          msg="release app exited during startup",
        )
        window = locate(child.pid)
        @async.sleep(50)
      }
      click(window, 170, 32)
      click(window, 170, 76)
      @async.sleep(1400)
      assert_true(child.try_wait() == None)
      send(window, 0x0010U, 0UL, 0L)
      assert_eq(child.wait(), 0)
    }
  })
  println(
    "QUOTE_BOARD_NATIVE_PACKAGE_RELOCATION_OK unrelated_cwd owned_window close",
  )
}
