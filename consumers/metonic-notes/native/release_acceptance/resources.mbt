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
async fn sample_release_resources(
  executable : String,
  directory : String,
  reopen : Bool,
) -> Json {
  @async.with_timeout(20000, async fn() {
    @async.with_task_group() <| group => {
      let child = @process.spawn(
        group,
        executable,
        [],
        cwd=directory,
        extra_env=Map([("METONIC_NOTES_DATA", directory + "/data")]),
        no_console_window=true,
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
      // WhyNot: locating the HWND alone does not prove the saved collection has loaded.
      @async.sleep(1000)
      let ready = process_resources(child.pid)
      click(window, 200, 140)
      type_text(window, "alpha")
      @async.sleep(500)
      let filtered = process_resources(child.pid)
      send(window, 0x0010U, 0UL, 0L)
      assert_eq(child.wait(), 0)
      { "reopen": reopen, "ready": ready, "filtered": filtered }
    }
  })
}

///|
async fn release_resource_sample(executable : String, fixture : String) -> Unit {
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
