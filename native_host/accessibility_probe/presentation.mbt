///|
struct CaptureMetadata {
  hwnd : Double
  width : Int
  height : Int
  processId : Int
} derive(FromJson)

///|
#borrow(rect)
extern "C" fn frame_bounds(
  hwnd : UInt64,
  attribute : UInt,
  rect : FixedArray[Int],
  size : UInt,
) -> Int = "DwmGetWindowAttribute"

///|
#borrow(point)
extern "C" fn client_origin(hwnd : UInt64, point : FixedArray[Int]) -> Int = "ClientToScreen"

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
  let frame = FixedArray::make(4, 0)
  let origin = FixedArray::make(2, 0)
  assert_eq(frame_bounds(hwnd, 9U, frame, 16U), 0)
  assert_true(client_origin(hwnd, origin) != 0)
  assert_eq(image.width, frame[2] - frame[0])
  assert_eq(image.height, frame[3] - frame[1])
  let expected_x = origin[0] - frame[0] + 260
  let expected_y = origin[1] - frame[1] + 144
  let mut cyan = 0
  let mut orange = 0
  let mut left = image.width
  let mut top = image.height
  let mut right = -1
  let mut bottom = -1
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
    let rectangle = if phase == "initial" {
      g > r + 70 && b > r + 70
    } else {
      r > g + 50 && g > b + 40
    }
    if rectangle {
      let x = index % image.width
      let y = index / image.width
      left = left.min(x)
      top = top.min(y)
      right = right.max(x)
      bottom = bottom.max(y)
    }
  }
  if phase == "initial" {
    assert_true(cyan > 500 && orange == 0)
  } else {
    assert_true(orange > 500 && cyan == 0)
  }
  assert_eq(left, expected_x)
  assert_eq(top, expected_y)
  assert_eq(right - left + 1, 120)
  assert_eq(bottom - top + 1, 72)
  assert_eq(cyan + orange, 120 * 72)
  stage("presentation colors and geometry verified " + phase)
}
