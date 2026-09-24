///|
extern "C" fn open_process(
  access : UInt,
  inherit_handle : Int,
  pid : UInt,
) -> UInt64 = "OpenProcess"

///|
extern "C" fn close_handle(handle : UInt64) -> Int = "CloseHandle"

///|
#borrow(counters)
extern "C" fn read_process_memory(
  process : UInt64,
  counters : FixedArray[UInt64],
  size : UInt,
) -> Int = "K32GetProcessMemoryInfo"

///|
#borrow(count)
extern "C" fn read_handle_count(
  process : UInt64,
  count : FixedArray[UInt],
) -> Int = "GetProcessHandleCount"

///|
fn process_resources(pid : Int) -> Json raise {
  let process = open_process(0x0410U, 0, pid.reinterpret_as_uint())
  assert_true(process != 0UL, msg="OpenProcess failed for release application")
  defer assert_true(close_handle(process) != 0)
  let counters = FixedArray::make(10, 0UL)
  counters[0] = 80UL
  assert_true(
    read_process_memory(process, counters, 80U) != 0,
    msg="GetProcessMemoryInfo failed for release application",
  )
  let count = FixedArray::make(1, 0U)
  assert_true(read_handle_count(process, count) != 0)
  assert_true(
    counters[2] <= 300UL * 1024UL * 1024UL,
    msg="Release working set exceeded 300 MiB",
  )
  assert_true(
    counters[9] <= 512UL * 1024UL * 1024UL,
    msg="Release private use exceeded 512 MiB",
  )
  assert_true(count[0] <= 800U, msg="Release handle count exceeded 800")
  {
    "working_set_bytes": counters[2].to_string(),
    "peak_working_set_bytes": counters[1].to_string(),
    "private_usage_bytes": counters[9].to_string(),
    "handle_count": count[0].reinterpret_as_int(),
  }
}

///|
async fn wait_memos(window : UInt64, expected : Int) -> Unit {
  @async.with_timeout(30000, () => {
    while uia_memos(window) != expected {
      @async.sleep(50)
    }
  })
}

///|
async fn wait_value(window : UInt64, name : String, expected : String) -> Unit {
  @async.with_timeout(30000, () => {
    while !uia_value_is(window, name, expected) {
      @async.sleep(50)
    }
  })
}

///|
async fn wait_saved(directory : String, text : String, position : Int) -> Unit {
  @async.with_timeout(30000, () => {
    let path = directory + "/data/snapshot"
    let mut verified = false
    while !verified {
      let document = @collection.decode(Some(@fs.read_file(path).text())).unwrap()
      let items = document.items()
      verified = items.length() == 1000 &&
        items[position].id == 10 &&
        document.find(10).unwrap().text == text
      if !verified {
        @async.sleep(50)
      }
    }
  })
}

///|
async fn verify_release_shutdown_log(path : String) -> Unit {
  let output = @fs.read_file(path).text()
  assert_true(
    output.contains("GPU_OWNERSHIP_RELEASED"),
    msg="Release renderer ownership was not cleared during shutdown",
  )
  assert_true(
    output.contains("WINDOW_CLEANUP_OK"),
    msg="Release window cleanup was not reported",
  )
}

///|
async fn sample_release_resources(
  executable : String,
  directory : String,
  reopen : Bool,
) -> Json {
  @async.with_timeout(120000, async fn() {
    @async.with_task_group() <| group => {
      let log_path = if reopen {
        directory + "/reopen-release.log"
      } else {
        directory + "/initial-release.log"
      }
      let log = @process.redirect_to_file(log_path)
      let child = @process.spawn(
        group,
        executable,
        [],
        cwd=directory,
        extra_env=Map([("METONIC_NOTES_DATA", directory + "/data")]),
        no_console_window=true,
        stdout=log,
        stderr=log,
        cancel_handler=@process.hard_cancel(),
      )
      let mut window = 0UL
      while window == 0UL {
        assert_true(
          child.try_wait() == None,
          msg="Release application exited during startup",
        )
        window = locate(child.pid)
        @async.sleep(50)
      }
      @async.sleep(1000)
      wait_memos(window, 1000)
      assert_true(uia_name_exists(window, "Memo 1000"))
      let ready = process_resources(child.pid)
      uia_set_value(window, "Search memos", "alpha")
      wait_memos(window, 100)
      assert_true(uia_value_is(window, "Search memos", "alpha"))
      assert_true(uia_name_exists(window, "Memo 10"))
      assert_false(uia_name_exists(window, "Memo 1"))
      let filtered = process_resources(child.pid)
      uia_invoke(window, "Memo 10")
      wait_value(
        window,
        "Memo",
        if reopen {
          "Memo 10 alpha autosaved"
        } else {
          "Memo 10 alpha"
        },
      )
      let selected = process_resources(child.pid)
      if reopen {
        let before_exit = process_resources(child.pid)
        send(window, 0x0010U, 0UL, 0L)
        assert_eq(child.wait(), 0)
        assert_eq(locate(child.pid), 0UL)
        verify_release_shutdown_log(log_path)
        return {
          "reopen": true,
          "ready": ready,
          "filtered": filtered,
          "selected": selected,
          "before_exit": before_exit,
          "exit_code": 0,
          "window_closed": true,
          "gpu_ownership_released": true,
        }
      }
      uia_set_value(window, "Search memos", "")
      wait_memos(window, 1000)
      let cleared = process_resources(child.pid)
      let mut scroll_row = ""
      let mut before_y = -1.0
      for id in 1..<=32 {
        let name = if id == 10 { "* Memo 10" } else { "Memo " + id.to_string() }
        let y = uia_y(window, name)
        if y >= 0.0 {
          scroll_row = name
          before_y = y
          break
        }
      }
      assert_true(scroll_row != "", msg="No visible release row had UIA bounds")
      send(window, 0x0200U, 0UL, (200 * 65536 + 40).to_int64())
      send(window, 0x020AU, 0xFF880000UL, 0L)
      @async.with_timeout(30000, () => {
        while uia_y(window, scroll_row) >= before_y {
          @async.sleep(50)
        }
      })
      let scrolled = process_resources(child.pid)
      uia_invoke(window, "Move up")
      @async.sleep(100)
      assert_true(uia_name_exists(window, "* Memo 10"))
      let reordered = process_resources(child.pid)
      uia_set_value(window, "Memo", "Memo 10 alpha edited")
      wait_value(window, "Memo", "Memo 10 alpha edited")
      let edited = process_resources(child.pid)
      uia_invoke(window, "Save all")
      wait_saved(directory, "Memo 10 alpha edited", 8)
      let saved = process_resources(child.pid)
      uia_set_value(window, "Memo", "Memo 10 alpha autosaved")
      wait_saved(directory, "Memo 10 alpha autosaved", 8)
      let autosaved = process_resources(child.pid)
      let before_exit = process_resources(child.pid)
      send(window, 0x0010U, 0UL, 0L)
      assert_eq(child.wait(), 0)
      assert_eq(locate(child.pid), 0UL)
      verify_release_shutdown_log(log_path)
      {
        "reopen": false,
        "ready": ready,
        "filtered": filtered,
        "selected": selected,
        "cleared": cleared,
        "scrolled": scrolled,
        "reordered": reordered,
        "edited": edited,
        "saved": saved,
        "autosaved": autosaved,
        "before_exit": before_exit,
        "exit_code": 0,
        "window_closed": true,
        "gpu_ownership_released": true,
      }
    }
  })
}

///|
async fn release_resource_sample(executable : String, fixture : String) -> Unit {
  assert_true(initialize_uia(0UL, 0U) >= 0)
  defer uninitialize_uia()
  let source = @fs.read_file(fixture)
  let document = @collection.decode(Some(source.text())).unwrap()
  assert_eq(document.items().length(), 1000)
  let temporary = @fs.tmpdir(prefix="metonic-release-resources-")
  let resolved = @fs.realpath(temporary)
  defer {
    assert_eq(@fs.realpath(temporary), resolved)
    @fs.rmdir(temporary, recursive=true)
  }
  @fs.mkdir(temporary + "/data")
  @fs.write_file(temporary + "/data/snapshot", source.binary())
  let initial = sample_release_resources(executable, temporary, false)
  let reopened = sample_release_resources(executable, temporary, true)
  let result : Json = { "initial": initial, "reopened": reopened }
  println("NOTES_RELEASE_RESOURCE_SAMPLE_OK " + result.stringify())
}
