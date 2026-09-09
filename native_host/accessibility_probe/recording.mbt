///|
extern "C" fn window_dpi(hwnd : UInt64) -> UInt = "GetDpiForWindow"

///|
async fn record_json(path : String) -> Json {
  assert_true(@fs.file_size(path) <= 65536L)
  @json.parse(@fs.read_file(path).text())
}

///|
async fn record_provenance(hwnd : UInt64, expected_pid : Int) -> Unit {
  if @env.get_env_var("METONIC_PRESENTATION_CAPTURE") != Some("1") {
    return
  }
  let owner = FixedArray::make(1, 0)
  assert_true(window_pid(hwnd, owner) != 0U)
  assert_eq(owner[0], expected_pid)
  let dpi = window_dpi(hwnd)
  assert_true(dpi > 0U)
  let root = ".work/recording-\{expected_pid}-\{@async.now()}"
  @fs.mkdir(root)
  let target : Json = {
    "hwnd": hwnd.to_string(),
    "pid": expected_pid,
    "dpi": dpi,
    "scope": "owned window; no screen capture; no application frame identity",
  }
  @fs.write_file(root + "/target.json", target.stringify())
  let output = @process.redirect_to_file(root + "/result.json")
  defer output.close()
  let errors = @process.redirect_to_file(root + "/stderr.log")
  defer errors.close()
  let cancel_test = @env.get_env_var("METONIC_RECORDING_CANCEL_TEST") ==
    Some("1")
  let completed = @async.with_timeout_opt(
    if cancel_test {
      1000
    } else {
      15000
    },
    () => {
      @process.run(
        ".work/winapp-assets/winapp.exe",
        [
          "ui",
          "record",
          "-w",
          hwnd.to_string(),
          "--duration-sec",
          if cancel_test {
            "10"
          } else {
            "1"
          },
          "--fps",
          "2",
          "--frames",
          "--json",
          "--output",
          root + "/capture.mp4",
        ],
        extra_env=Map([("WINAPP_CLI_TELEMETRY_OPTOUT", "1")]),
        stdout=output,
        stderr=errors,
        no_console_window=true,
        cancel_handler=@process.hard_cancel(),
      )
    },
  )
  if cancel_test {
    assert_true(completed is None)
    stage("recording cancellation joined owned process: " + root)
    return
  }
  guard completed == Some(0) else {
    fail("recording failed or timed out; inspect " + root)
  }
  assert_true(window_pid(hwnd, owner) != 0U)
  assert_eq(owner[0], expected_pid)
  assert_eq(window_dpi(hwnd), dpi)
  let result = record_json(root + "/result.json")
  let frames = root + "/capture.frames"
  let manifest = record_json(frames + "/manifest.json")
  assert_true(@fs.file_size(frames + "/frames.ndjson") <= 65536L)
  let samples : Array[Json] = []
  for line in @fs.read_file(frames + "/frames.ndjson").text().split("\n") {
    if !line.trim().is_empty() {
      samples.push(@json.parse(line))
    }
  }
  let evidence = @recording.validate(result, manifest, samples)
  assert_true(@fs.file_size(root + "/capture.mp4") > 0L)
  for file in evidence.files {
    let path = frames + "/" + file
    let size = @fs.file_size(path)
    assert_true(size > 4L && size <= 16777216L)
    let data = @fs.read_file(path).binary()
    assert_true(data[0] == b'\xff' && data[1] == b'\xd8')
    assert_true(
      data[data.length() - 2] == b'\xff' && data[data.length() - 1] == b'\xd9',
    )
  }
  let verified : Json = {
    "mode": evidence.mode,
    "samples": evidence.samples,
    "width": evidence.width,
    "height": evidence.height,
    "pid": expected_pid,
    "hwnd": hwnd.to_string(),
    "dpi": dpi,
    "source": "winapp recording; separate from screenshot PNGs",
  }
  @fs.write_file(root + "/verified.json", verified.stringify())
  stage("recording provenance " + evidence.mode + ": " + root)
}
