///|
struct CaptureMetadata {
  hwnd : Double
  width : Int
  height : Int
  processId : Int
} derive(FromJson)

///|
let long_result_pixels : Ref[Bytes?] = { val: None, }

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
async fn capture_presentation(
  hwnd : UInt64,
  phase : String,
  editor_text? : String? = None,
  caret? : Int? = None,
  query_text? : String? = None,
  result_text? : String? = None,
) -> Unit {
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
  let scene_x = if phase == "initial" || phase == "toggled" {
    260
  } else if phase == "compact-completed" {
    240
  } else {
    250
  }
  let expected_x = origin[0] - frame[0] + scene_x
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
  let reference_text = if phase == "initial" {
    Some("日本語の描画を確認します ABC 123")
  } else {
    editor_text
  }
  if reference_text is Some(text) {
    let client = FixedArray::make(4, 0)
    assert_true(client_rect(hwnd, client) != 0)
    let width = (client[2] - 16).max(1).min(640)
    let engine = @raster.create(
      @fs.read_file(".work/text-assets/NotoSansJP.ttf").binary(),
    ).unwrap()
    let expected = @raster.render(engine, text, width, 96, caret~)
    let x0 = origin[0] - frame[0] + 8
    let y0 = origin[1] - frame[1] + 8
    let mut black = 0
    let mut white = 0
    // Antialiased edges change with surface color conversion; only opaque
    // black and white establish this transfer/placement contract.
    for y in 0..<96 {
      for x in 0..<width {
        let source = (y * width + x) * 4
        let target = ((y0 + y) * image.width + x0 + x) * 4
        if expected[source] == b'\x00' &&
          expected[source + 1] == b'\x00' &&
          expected[source + 2] == b'\x00' {
          black += 1
          for channel in 0..<3 {
            assert_true(image.data[target + channel] <= b'\x02')
          }
        } else if expected[source] == b'\xFF' &&
          expected[source + 1] == b'\xFF' &&
          expected[source + 2] == b'\xFF' {
          white += 1
          for channel in 0..<3 {
            assert_true(image.data[target + channel] >= b'\xFD')
          }
        }
      }
    }
    assert_true(white > width * 40)
    if text != "" {
      assert_true(black > 100)
    }
    stage("editor glyph interiors, caret and background match raster " + phase)
  }
  let client = FixedArray::make(4, 0)
  assert_true(client_rect(hwnd, client) != 0)
  let editor_width = (client[2] - 16).max(1).min(640)
  for region in [
    ("query", query_text, 232, 106, (editor_width - 232).max(1), 28),
    ("result", result_text, 8, 104, editor_width.min(176), 32),
  ] {
    let (name, text, x, y, width, height) = region
    if text is Some(text) {
      let engine = @raster.create(
        @fs.read_file(".work/text-assets/NotoSansJP.ttf").binary(),
      ).unwrap()
      let expected = @raster.render(engine, text, width, 32)
      let x0 = origin[0] - frame[0] + x
      let y0 = origin[1] - frame[1] + y
      assert_true(x0 >= 0 && y0 >= 0 && x0 + width <= image.width &&
        y0 + height <= image.height)
      let mut ink = 0
      let mut background = 0
      // Query borders clip the final four raster rows; compare only its interior.
      // Surface color conversion prevents exact antialiased-edge comparisons.
      for row in 0..<height {
        for column in 0..<width {
          let source = (row * width + column) * 4
          let target = ((y0 + row) * image.width + x0 + column) * 4
          let black = expected[source] == b'\x00' &&
            expected[source + 1] == b'\x00' && expected[source + 2] == b'\x00'
          let white = expected[source] == b'\xFF' &&
            expected[source + 1] == b'\xFF' && expected[source + 2] == b'\xFF'
          if black || white {
            if black { ink += 1 } else { background += 1 }
            for channel in 0..<3 {
              assert_true(
                if black { image.data[target + channel] <= b'\x02' }
                else { image.data[target + channel] >= b'\xFD' },
                msg=name + " presented pixels differ at " + column.to_string() +
                  "," + row.to_string() + " during " + phase,
              )
            }
          }
        }
      }
      assert_true(background > width * height / 3)
      if text != "" { assert_true(ink > 0) }
      stage(name + " glyph interiors and background match raster " + phase)
    }
  }
  if phase == "long-editor" || phase == "result" {
    let mut status_ink = 0
    let x0 = origin[0] - frame[0] + 8
    let y0 = origin[1] - frame[1] + 104
    for y in y0..<(y0 + 32) {
      for x in x0..<(x0 + 200) {
        let offset = (y * image.width + x) * 4
        if image.data[offset] < b'\x50' &&
          image.data[offset + 1] < b'\x50' &&
          image.data[offset + 2] < b'\x50' {
          status_ink += 1
        }
      }
    }
    assert_true(
      status_ink > 20,
      msg="HTTP result is not visible below the editor",
    )
    let row = Bytes::makei(200 * 32 * 4, index => {
      let y = index / (200 * 4)
      let x_byte = index % (200 * 4)
      image.data[((y0 + y) * image.width + x0) * 4 + x_byte]
    })
    if phase == "long-editor" {
      long_result_pixels.val = Some(row)
    } else {
      assert_eq(
        row,
        long_result_pixels.val.unwrap(),
        msg="editor content changed the result row",
      )
    }
  }
  stage("presentation colors and geometry verified " + phase)
}
