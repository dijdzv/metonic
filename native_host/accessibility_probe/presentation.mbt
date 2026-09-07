///|
struct CaptureMetadata {
  hwnd : Double
  width : Int
  height : Int
  processId : Int
} derive(FromJson)

///|
async fn capture_presentation(hwnd : UInt64, phase : String) -> Unit {
  if @env.get_env_var("METONIC_PRESENTATION_CAPTURE") != Some("1") {
    return
  }
  @fs.write_file(".work/presentation-" + phase + ".png", b"")
  let (code, output, errors) = @process.collect_output(
    ".work/winapp-assets/winapp.exe",
    [
      "ui",
      "screenshot",
      "-w",
      hwnd.to_string(),
      "--json",
      "--output",
      ".work/presentation-" + phase + ".png",
    ],
    extra_env=Map([("WINAPP_CLI_TELEMETRY_OPTOUT", "1")]),
    no_console_window=true,
  )
  stage("capture " + phase + " " + output.text())
  guard code == 0 else { fail("capture failed: " + errors.text()) }
  let metadata : CaptureMetadata = @json.from_json(@json.parse(output.text()))
  let owner = FixedArray::make(1, 0)
  ignore(window_pid(hwnd, owner))
  assert_eq(metadata.hwnd, hwnd.to_double())
  assert_eq(metadata.processId, owner[0])
  let image = @image.decode_png(
    @fs.read_file(".work/presentation-" + phase + ".png").binary(),
  )
  assert_eq(image.width, metadata.width)
  assert_eq(image.height, metadata.height)
  let mut cyan = 0
  let mut orange = 0
  for index in 0..<(image.width * image.height) {
    let offset = index * 4
    let r = image.data[offset].to_int()
    let g = image.data[offset + 1].to_int()
    let b = image.data[offset + 2].to_int()
    if g > r + 70 && b > r + 70 {
      cyan += 1
    }
    if r > g + 50 && g > b + 40 {
      orange += 1
    }
  }
  if phase == "initial" {
    assert_true(cyan > 500 && orange == 0)
  } else {
    assert_true(orange > 500 && cyan == 0)
  }
  stage("presentation colors verified " + phase)
}
