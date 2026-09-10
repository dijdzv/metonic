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
extern "C" fn post(
  hwnd : UInt64,
  message : UInt,
  wparam : UInt64,
  lparam : Int64,
) -> Int = "PostMessageW"

///|
extern "C" fn is_window(hwnd : UInt64) -> Int = "IsWindow"

///|
extern "C" fn visible(hwnd : UInt64) -> Int = "IsWindowVisible"

///|
fn owned_window(pid : Int) -> UInt64 {
  let owner = FixedArray::make(1, 0)
  let mut cursor = 0UL
  for _ in 0..<4096 {
    cursor = next_window(0UL, cursor, 0UL, 0UL)
    if cursor == 0UL {
      return 0UL
    }
    ignore(window_pid(cursor, owner))
    if owner[0] == pid && visible(cursor) != 0 {
      return cursor
    }
  }
  0UL
}

///|
async fn verify_close(system_key : Bool) -> Unit raise Error {
  @async.with_timeout(15000, async fn() {
    @async.with_task_group() <| group => {
      let executable = @fs.realpath(
        ".work/native-host-build/native/release/build/local/native_host/window_app/window_app.exe",
      )
      let child = @process.spawn(
        group,
        executable,
        [],
        no_console_window=true,
        cancel_handler=@process.hard_cancel(),
      )
      let mut hwnd = 0UL
      while hwnd == 0UL {
        guard child.try_wait() is None else {
          fail("production host exited before creating a window")
        }
        hwnd = owned_window(child.pid)
        @async.sleep(20)
      }
      @async.sleep(500)
      guard child.try_wait() is None else {
        fail("production host exited during initialization")
      }
      let sent = if system_key {
        println("WINDOW_RELEASE_SYSTEM_KEY_CLOSE_BEGIN")
        post(hwnd, 0x0104U, 0x73UL, 0x203e0001L)
      } else {
        post(hwnd, 0x0010U, 0UL, 0L)
      }
      guard sent != 0 else { fail("production close request failed") }
      guard child.wait() == 0 else {
        fail("production host failed during shutdown")
      }
      guard is_window(hwnd) == 0 else {
        fail("production window survived shutdown")
      }
      println(
        if system_key {
          "WINDOW_RELEASE_SYSTEM_KEY_CLOSE_OK"
        } else {
          "WINDOW_RELEASE_LIFECYCLE_OK owned_process_start_close"
        },
      )
    }
  })
}

///|
async fn main {
  verify_close(false)
  verify_close(true)
}
