///|
extern "C" fn post_window_message(
  window : UInt64,
  message : UInt,
  key : UInt64,
  point : Int64,
) -> Int = "PostMessageW"

///|
extern "C" fn current_process_handle() -> UInt64 = "GetCurrentProcess"

///|
#borrow(counters)
extern "C" fn process_memory_info(
  process : UInt64,
  counters : FixedArray[UInt64],
  size : UInt,
) -> Int = "K32GetProcessMemoryInfo"

///|
fn process_working_set() -> (UInt64, UInt64) raise {
  // WhyNot: the Windows working set does not include GPU allocations.
  let counters = FixedArray::make(9, 0UL)
  counters[0] = 72UL
  assert_true(process_memory_info(current_process_handle(), counters, 72U) != 0)
  (counters[2], counters[1])
}

///|
fn gpu_resource_json(value : @gpu.SurfaceGpuResources) -> Json {
  {
    "text_texture_count": value.text_texture_count,
    "text_texture_bytes": value.text_texture_bytes.to_string(),
    "peak_text_texture_count": value.peak_text_texture_count,
    "peak_text_texture_bytes": value.peak_text_texture_bytes.to_string(),
    "retained_frame_count": value.retained_frame_count,
    "retained_frame_bytes": value.retained_frame_bytes.to_string(),
    "uniform_buffer_bytes": value.uniform_buffer_bytes.to_string(),
    "closed": value.closed,
  }
}

///|
fn assert_gpu_resources(value : @gpu.SurfaceGpuResources) -> Unit raise {
  assert_false(value.closed)
  assert_true(value.text_texture_count > 0)
  assert_true(value.text_texture_count <= 24)
  assert_true(value.peak_text_texture_count <= 48)
  assert_true(value.text_texture_bytes <= 2UL * 1024UL * 1024UL)
  assert_true(value.peak_text_texture_bytes <= 4UL * 1024UL * 1024UL)
  assert_true(value.peak_text_texture_count >= value.text_texture_count)
  assert_true(value.peak_text_texture_bytes >= value.text_texture_bytes)
  // WhyNot: debug frame retention is not part of the release renderer's GPU footprint.
  assert_true(value.retained_frame_count <= 2)
  assert_eq(value.uniform_buffer_bytes, 32UL)
}

///|
async fn main {
  let directory = @env.get_env_var("METONIC_NOTES_DATA").unwrap()
  let storage = @storage.create(directory)
  let application = @model.create_collection(storage.adapter(), () => {
    storage.dispose()
  })
  let observed : Ref[@window_host.Observation?] = Ref(None)
  let complete = Ref(false)
  let measurements : Ref[Json?] = Ref(None)
  let reopening = @env.get_env_var("METONIC_SCALE_REOPEN") == Some("1")
  let start = @async.now()
  @window_host.run(
    minimum_size=Some((320, 360)),
    @host.from_application(application),
    hidden=true,
    report=_ => (),
    observer=Some(value => observed.val = Some(value)),
    controller=Some(handle => {
      @async.with_timeout(120000, () => {
        while (application.view)().last().unwrap().element.text == "Loading..." {
          @async.sleep(5)
        }
        let row_count = () => {
          @semantics.snapshot(application.editor)
          .filter(node => node.name.contains("Memo "))
          .length()
        }
        assert_eq(row_count(), 1000)
        assert_true((application.view)().length() <= 42)
        ignore((handle.capture)(_ => ()))
        let gpu_ready = (handle.gpu_resources)().unwrap()
        assert_gpu_resources(gpu_ready)
        let startup = (@async.now() - start).to_int()
        let (initial_working_set, _) = process_working_set()
        let target = name => {
          @semantics.snapshot(application.editor)
          .iter()
          .find_first(node => node.name == name)
          .unwrap().reference
        }
        let operate = (reference, action) => {
          assert_eq(
            (handle.operate)(
              reference,
              action,
              @semantics.revision(application.editor),
            ),
            "",
          )
        }
        let wait_rows = count => {
          @async.with_timeout(30000, () => {
            while row_count() != count {
              @async.sleep(5)
            }
          })
        }
        let search = target("Search memos")
        if reopening {
          let restore_start = @async.now()
          operate(search, @window_host.InsertText("alpha"))
          wait_rows(100)
          operate(target("Memo 10"), @window_host.ActivateControl)
          assert_eq((handle.inspect)().text, "Memo 10 alpha autosaved")
          ignore((handle.capture)(_ => ()))
          let gpu_reopened = (handle.gpu_resources)().unwrap()
          assert_gpu_resources(gpu_reopened)
          measurements.val = Some({
            "reopen_ms": startup,
            "restore_selection_ms": (@async.now() - restore_start).to_int(),
            "working_set_bytes": process_working_set().0.to_string(),
            "gpu_ready": gpu_resource_json(gpu_ready),
            "gpu_reopened": gpu_resource_json(gpu_reopened),
          })
          println(
            "NOTES_SCALE_NATIVE_REOPEN_OK " +
            measurements.val.unwrap().stringify(),
          )
          complete.val = true
          (handle.apply)(@window_host.Close)
          return
        }
        let search_start = @async.now()
        operate(search, @window_host.InsertText("alpha"))
        wait_rows(100)
        ignore((handle.capture)(_ => ()))
        let search_ms = (@async.now() - search_start).to_int()
        let select_start = @async.now()
        operate(target("Memo 10"), @window_host.ActivateControl)
        assert_eq((handle.inspect)().text, "Memo 10 alpha")
        ignore((handle.capture)(_ => ()))
        let select_ms = (@async.now() - select_start).to_int()
        let clear_start = @async.now()
        operate(search, @window_host.SelectRange(0, 5))
        operate(search, @window_host.InsertText(""))
        wait_rows(1000)
        let initial = (handle.capture)(_ => ())
        let clear_ms = (@async.now() - clear_start).to_int()
        let first_row = target("Memo 1")
        let before = (handle.inspect)().frames
        let window = observed.val.unwrap().hwnd
        let scroll_start = @async.now()
        assert_true(
          post_window_message(
            window,
            0x200U,
            0UL,
            (200 * 65536 + 40).to_int64(),
          ) !=
          0,
        )
        assert_true(post_window_message(window, 0x20AU, 0xFF880000UL, 0L) != 0)
        @async.with_timeout(30000, () => {
          while (handle.inspect)().frames <= before ||
                (application.view)()
                .iter()
                .find_first(control => {
                  control.element.reference == Some(first_row)
                })
                is Some(_) {
            @async.sleep(5)
          }
        })
        let scrolled = (handle.capture)(_ => ())
        assert_false(scrolled.pixels == initial.pixels)
        let scroll_ms = (@async.now() - scroll_start).to_int()
        let reorder_start = @async.now()
        operate(target("Move up"), @window_host.ActivateControl)
        assert_true(
          (application.view)()
          .iter()
          .find_first(control => control.element.text == "* Memo 10")
          is Some(_),
        )
        ignore((handle.capture)(_ => ()))
        let reorder_ms = (@async.now() - reorder_start).to_int()
        let edit_start = @async.now()
        let editor = application.default_input.unwrap()
        operate(editor, @window_host.SelectRange(0, "Memo 10 alpha".length()))
        operate(editor, @window_host.InsertText("Memo 10 alpha edited"))
        assert_eq((handle.inspect)().text, "Memo 10 alpha edited")
        ignore((handle.capture)(_ => ()))
        let edit_ms = (@async.now() - edit_start).to_int()
        let save_start = @async.now()
        operate(target("Save all"), @window_host.ActivateControl)
        @async.with_timeout(30000, () => {
          while !@fs.read_file(directory + "/snapshot")
                .text()
                .contains("Memo 10 alpha edited") ||
                !(application.can_close)() {
            @async.sleep(5)
          }
        })
        ignore((handle.capture)(_ => ()))
        let save_ms = (@async.now() - save_start).to_int()
        let autosave_start = @async.now()
        operate(
          editor,
          @window_host.SelectRange(0, "Memo 10 alpha edited".length()),
        )
        operate(editor, @window_host.InsertText("Memo 10 alpha autosaved"))
        assert_eq((handle.inspect)().text, "Memo 10 alpha autosaved")
        @async.with_timeout(30000, () => {
          while !@fs.read_file(directory + "/snapshot")
                .text()
                .contains("Memo 10 alpha autosaved") ||
                !(application.can_close)() {
            @async.sleep(5)
          }
        })
        let autosave_ms = (@async.now() - autosave_start).to_int()
        let (working_set, peak_working_set) = process_working_set()
        let gpu_final = (handle.gpu_resources)().unwrap()
        assert_gpu_resources(gpu_final)
        measurements.val = Some({
          "startup_ms": startup,
          "search100_ms": search_ms,
          "select_ms": select_ms,
          "clear_search_ms": clear_ms,
          "scroll_ms": scroll_ms,
          "reorder_ms": reorder_ms,
          "edit_ms": edit_ms,
          "save_ms": save_ms,
          "autosave_ms": autosave_ms,
          "rows": 1000,
          "initial_working_set_bytes": initial_working_set.to_string(),
          "working_set_bytes": working_set.to_string(),
          "peak_working_set_bytes": peak_working_set.to_string(),
          "gpu_ready": gpu_resource_json(gpu_ready),
          "gpu_final": gpu_resource_json(gpu_final),
        })
        println(
          "NOTES_SCALE_NATIVE_OK " + measurements.val.unwrap().stringify(),
        )
        complete.val = true
        (handle.apply)(@window_host.Close)
      })
    }),
  )
  assert_true(complete.val)
  assert_true(measurements.val is Some(_))
}
