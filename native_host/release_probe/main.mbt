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
extern "C" fn window_title_length(hwnd : UInt64) -> Int = "GetWindowTextLengthW"

///|
#borrow(text)
extern "C" fn window_title(
  hwnd : UInt64,
  text : FixedArray[Byte],
  capacity : Int,
) -> Int = "GetWindowTextW"

///|
fn owned_window(pid : Int) -> UInt64 raise {
  let owner = FixedArray::make(1, 0)
  let title = FixedArray::make(16, b'\x00')
  let expected : FixedArray[Byte] = [
    b'M', 0, b'e', 0, b't', 0, b'o', 0, b'n', 0, b'i', 0, b'c', 0, 0, 0,
  ]
  let mut selected = 0UL
  let mut cursor = 0UL
  for _ in 0..<4096 {
    cursor = next_window(0UL, cursor, 0UL, 0UL)
    if cursor == 0UL {
      return selected
    }
    if window_pid(cursor, owner) != 0U &&
      owner[0] == pid &&
      visible(cursor) != 0 &&
      window_title_length(cursor) == 7 &&
      window_title(cursor, title, 8) == 7 &&
      title == expected {
      guard selected == 0UL else { fail("multiple owned Metonic windows") }
      selected = cursor
    }
  }
  fail("owned window enumeration exceeded its bound")
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
      let mut stage = "waiting-window"
      let mut completed = false
      defer (if !completed {
        let process = match child.try_wait() {
          Some(code) => code.to_string()
          None => "running"
        }
        println(
          "WINDOW_RELEASE_CLOSE_FAILURE system_key=" +
          system_key.to_string() +
          " stage=" +
          stage +
          " pid=" +
          child.pid.to_string() +
          " hwnd=" +
          hwnd.to_string() +
          " window=" +
          is_window(hwnd).to_string() +
          " visible=" +
          visible(hwnd).to_string() +
          " process=" +
          process,
        )
      })
      while hwnd == 0UL {
        guard child.try_wait() is None else {
          fail("production host exited before creating a window")
        }
        hwnd = owned_window(child.pid)
        @async.sleep(20)
      }
      stage = "initialization-delay"
      @async.sleep(500)
      guard child.try_wait() is None else {
        fail("production host exited during initialization")
      }
      stage = "posting-close"
      let sent = if system_key {
        println("WINDOW_RELEASE_SYSTEM_KEY_CLOSE_BEGIN")
        post(hwnd, 0x0104U, 0x73UL, 0x203e0001L)
      } else {
        post(hwnd, 0x0010U, 0UL, 0L)
      }
      guard sent != 0 else { fail("production close request failed") }
      stage = "waiting-process-exit"
      guard child.wait() == 0 else {
        fail("production host failed during shutdown")
      }
      stage = "checking-window-destruction"
      guard is_window(hwnd) == 0 else {
        fail("production window survived shutdown")
      }
      completed = true
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
