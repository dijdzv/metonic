///|
#external
pub type Page

///|
extern "js" fn snapshot_raw(page : Page) -> @js_async.Promise[String] =
  #| async (page) => JSON.stringify(await page.evaluate(() => window.metonicAsyncProbe.snapshot()))

///|
extern "js" fn action(
  page : Page,
  name : String,
  a : Int,
  b : Int,
  failure : Bool,
) -> @js_async.Promise[Unit] =
  #| async (page, name, a, b, failure) => { if (name === 'start') await page.evaluate(([x,y,z]) => window.metonicAsyncProbe.start(x,y,z), [a,b,failure]); else if (name === 'cancel') await page.evaluate(() => window.metonicAsyncProbe.cancel()); else if (name === 'reset') await page.locator('#reset').click(); else if (name === 'stop') await page.locator('#stop').click(); else if (name === 'key') { await page.locator('canvas').focus(); await page.keyboard.press('ArrowRight'); } }

///|
extern "js" fn can_start(page : Page) -> @js_async.Promise[Bool] =
  #| async (page) => await page.evaluate(() => window.metonicAsyncProbe.start(1, 1))

///|
extern "js" fn text(
  page : Page,
  selector : String,
) -> @js_async.Promise[String] =
  #| async (page, selector) => await page.locator(selector).innerText()

///|
extern "js" fn screenshot(
  page : Page,
  path : String,
) -> @js_async.Promise[String] =
  #| async (page, path) => { const bytes = await page.locator('canvas').screenshot({ path }); return bytes.toString('base64'); }

///|
extern "js" fn monotonic_ms() -> Double =
  #| () => performance.now()

///|
extern "js" fn sleep(milliseconds : Int) -> @js_async.Promise[Unit] =
  #| (milliseconds) => new Promise(resolve => setTimeout(resolve, milliseconds))

///|
pub suberror VerifyFailure {
  Failure(String)
} derive(Debug)

///|
fn fail(message : String) -> Unit raise VerifyFailure {
  raise Failure(message)
}

///|
fn require(value : Bool, message : String) -> Unit raise VerifyFailure {
  if !value {
    fail(message)
  }
}

///|
fn parse(raw : String) -> Json raise VerifyFailure {
  @json.parse(raw) catch {
    _ => {
      fail("invalid snapshot JSON")
      Json::object({})
    }
  }
}

///|
fn field(value : Json, key : String) -> Json? {
  match value {
    Json::Object(values) => values.get(key)
    _ => None
  }
}

///|
fn ints(
  value : Json,
  key : String,
  count : Int,
) -> Array[Int] raise VerifyFailure {
  let values = match field(value, key) {
    Some(Json::Array(values)) => values
    _ => {
      fail("missing " + key)
      []
    }
  }
  require(values.length() == count, key + " length")
  let result : Array[Int] = []
  for item in values {
    match item {
      Json::Number(n, ..) if n.to_int().to_double() == n =>
        result.push(n.to_int())
      _ => {
        fail("non numeric " + key)
        return []
      }
    }
  }
  result
}

///|
fn state(value : Json) -> Array[Int] raise VerifyFailure {
  let task = ints(value, "task", 6)
  let pending = int_field(value, "pending")
  require(pending >= 0, "pending")
  task
}

///|
fn int_field(value : Json, key : String) -> Int raise VerifyFailure {
  match field(value, key) {
    Some(Json::Number(n, ..)) if n.to_int().to_double() == n => n.to_int()
    _ => {
      fail("missing integer " + key)
      0
    }
  }
}

///|
fn bool_field(value : Json, key : String) -> Bool raise VerifyFailure {
  match field(value, key) {
    Some(Json::True) => true
    Some(Json::False) => false
    _ => {
      fail("missing boolean " + key)
      false
    }
  }
}

///|
fn text_int(value : String, key : String) -> Int raise VerifyFailure {
  @string.parse_int(value) catch {
    _ => {
      fail("invalid integer " + key)
      0
    }
  }
}

///|
fn check_pixel_bounds(
  width : Int,
  height : Int,
  min_x : Int,
  min_y : Int,
  max_x : Int,
  max_y : Int,
) -> Unit raise VerifyFailure {
  require(width > 0 && height > 0, "empty screenshot")
  require(
    min_x >= 0 && min_y >= 0 && max_x < width && max_y < height,
    "pixel bounds",
  )
  require(max_x >= min_x && max_y >= min_y, "empty teal bounds")
}

///|
fn check_png(raw64 : String, expected_x : Int) -> Unit raise VerifyFailure {
  let raw = @base64.decode(raw64) catch {
    _ => {
      fail("invalid PNG")
      Bytes::from_array([])
    }
  }
  let image = @image.decode_png(raw) catch {
    _ => {
      fail("invalid PNG")
      @image.ImageData::{
        width: 1,
        height: 1,
        data: Bytes::from_array([0, 0, 0, 0]),
      }
    }
  }
  let mut min_x = image.width
  let mut min_y = image.height
  let mut max_x = -1
  let mut max_y = -1
  for index = 0; index < image.data.length(); index = index + 4 {
    let pixel = index / 4
    let x = pixel % image.width
    let y = pixel / image.width
    if image.data[index].to_int() < 100 &&
      image.data[index + 1].to_int() > 120 &&
      image.data[index + 2].to_int() > 120 {
      min_x = if x < min_x { x } else { min_x }
      min_y = if y < min_y { y } else { min_y }
      max_x = if x > max_x { x } else { max_x }
      max_y = if y > max_y { y } else { max_y }
    }
  }
  check_pixel_bounds(image.width, image.height, min_x, min_y, max_x, max_y)
  require((min_x - expected_x).abs() <= 1, "teal x")
  require((max_x - min_x + 1 - 120).abs() <= 1, "teal width")
}

///|
fn check_png_dimensions(raw64 : String) -> Unit raise VerifyFailure {
  let raw = @base64.decode(raw64) catch {
    _ => {
      fail("invalid PNG")
      Bytes::from_array([])
    }
  }
  let image = @image.decode_png(raw) catch {
    _ => {
      fail("invalid PNG")
      @image.ImageData::{
        width: 1,
        height: 1,
        data: Bytes::from_array([0, 0, 0, 0]),
      }
    }
  }
  require(image.width > 0 && image.height > 0, "invalid final PNG dimensions")
}

///|
async fn read(page : Page) -> Json raise VerifyFailure {
  let raw = @js_async.Promise::wait(snapshot_raw(page)) catch {
    _ => {
      fail("snapshot failed")
      ""
    }
  }
  parse(raw)
}

///|
async fn read_text_int(
  page : Page,
  selector : String,
) -> Int raise VerifyFailure {
  let value = @js_async.Promise::wait(text(page, selector)) catch {
    _ => {
      fail(selector)
      ""
    }
  }
  text_int(value, selector)
}

///|
async fn wait_state(
  page : Page,
  task0 : Int,
  task2 : Int,
  pending : Int,
) -> Json raise VerifyFailure {
  let deadline = monotonic_ms() + 3000.0
  while monotonic_ms() < deadline {
    let value = read(page)
    let task = state(value)
    let current = int_field(value, "pending")
    if monotonic_ms() <= deadline &&
      task[0] == task0 &&
      task[2] == task2 &&
      current == pending {
      return value
    }
    @js_async.Promise::wait(sleep(25)) catch {
      _ => fail("timer failed")
    }
  }
  fail("25ms polling exceeded 3s deadline")
  Json::object({})
}

///|
async fn verify_checked(
  page : Page,
  target : String,
  out : String,
) -> String raise VerifyFailure {
  let initial = read(page)
  require(state(initial)[0] == 0, target + " initial")
  @js_async.Promise::wait(action(page, "start", 500, 40, false)) catch {
    _ => fail("start")
  }
  let before = read_text_int(page, "#revision")
  @js_async.Promise::wait(action(page, "key", 0, 0, false)) catch {
    _ => fail("key")
  }
  let mut changed = false
  let deadline = monotonic_ms() + 3000.0
  let mut now = before
  while monotonic_ms() < deadline {
    now = read_text_int(page, "#revision")
    if monotonic_ms() <= deadline && now > before {
      changed = true
      break
    }
    @js_async.Promise::wait(sleep(25)) catch {
      _ => fail("timer")
    }
  }
  require(changed, target + " revision deadline")
  let pending = wait_state(page, 1, 0, 1)
  require(
    pending.stringify() != initial.stringify(),
    target + " pending changed",
  )
  ignore(
    @js_async.Promise::wait(
      screenshot(page, out + "/" + target + "-pending.png"),
    ) catch {
      _ => {
        fail("pending screenshot")
        ""
      }
    },
  )
  let success = wait_state(page, 2, 40, 0)
  let success_png = @js_async.Promise::wait(
    screenshot(page, out + "/" + target + "-success.png"),
  ) catch {
    _ => {
      fail("success screenshot")
      ""
    }
  }
  check_png(success_png, 40)
  @js_async.Promise::wait(action(page, "start", 150, 70, false)) catch {
    _ => fail("supersede")
  }
  @js_async.Promise::wait(action(page, "start", 10, 90, false)) catch {
    _ => fail("supersede2")
  }
  let superseded = wait_state(page, 2, 90, 0)
  require(
    int_field(superseded, "rejected") == int_field(success, "rejected") + 1,
    target + " superseded rejection",
  )
  let superseded_png = @js_async.Promise::wait(
    screenshot(page, out + "/" + target + "-superseded.png"),
  ) catch {
    _ => {
      fail("superseded screenshot")
      ""
    }
  }
  check_png(superseded_png, 90)
  let submitted = read_text_int(page, "#submitted")
  @js_async.Promise::wait(action(page, "start", 100, 110, false)) catch {
    _ => fail("cancel start")
  }
  @js_async.Promise::wait(action(page, "cancel", 0, 0, false)) catch {
    _ => fail("cancel")
  }
  let canceled = wait_state(page, 4, 90, 0)
  require(
    submitted == read_text_int(page, "#submitted"),
    target + " cancel stability",
  )
  let submitted_before_fail = read_text_int(page, "#submitted")
  @js_async.Promise::wait(action(page, "start", 10, 7, true)) catch {
    _ => fail("failure start")
  }
  let failed = wait_state(page, 3, 90, 0)
  require(ints(failed, "task", 6)[3] == 7, target + " failure error")
  require(
    read_text_int(page, "#submitted") == submitted_before_fail,
    target + " failure submit",
  )
  let reset_before = read_text_int(page, "#submitted")
  @js_async.Promise::wait(action(page, "start", 100, 120, false)) catch {
    _ => fail("reset start")
  }
  @js_async.Promise::wait(action(page, "reset", 0, 0, false)) catch {
    _ => fail("reset")
  }
  let reset = wait_state(page, 0, 0, 0)
  let reset_deadline = monotonic_ms() + 3000.0
  let mut reset_submitted = read_text_int(page, "#submitted")
  while reset_submitted <= reset_before && monotonic_ms() < reset_deadline {
    @js_async.Promise::wait(sleep(25)) catch {
      _ => fail("reset polling")
    }
    reset_submitted = read_text_int(page, "#submitted")
  }
  require(
    reset_submitted > reset_before && monotonic_ms() <= reset_deadline,
    target + " reset submit",
  )
  @js_async.Promise::wait(sleep(200)) catch {
    _ => fail("reset timer")
  }
  require(
    reset_submitted == read_text_int(page, "#submitted"),
    target + " reset stable",
  )
  require(
    reset.stringify() == read(page).stringify(),
    target + " reset snapshot stable",
  )
  let submitted_before_stop = read_text_int(page, "#submitted")
  @js_async.Promise::wait(action(page, "start", 100, 130, false)) catch {
    _ => fail("stop start")
  }
  @js_async.Promise::wait(action(page, "stop", 0, 0, false)) catch {
    _ => fail("stop")
  }
  let stopped = wait_state(page, 5, 0, 0)
  require(bool_field(stopped, "disposed"), target + " disposed")
  @js_async.Promise::wait(sleep(200)) catch {
    _ => fail("stop timer")
  }
  require(
    stopped.stringify() == read(page).stringify(),
    target + " stop stable",
  )
  require(
    read_text_int(page, "#submitted") == submitted_before_stop,
    target + " stop submit",
  )
  let restart = @js_async.Promise::wait(can_start(page)) catch {
    _ => {
      fail("restart probe")
      false
    }
  }
  require(!restart, target + " restart")
  let final_png = @js_async.Promise::wait(
    screenshot(page, out + "/" + target + "-final.png"),
  ) catch {
    _ => {
      fail("final screenshot")
      ""
    }
  }
  check_png_dimensions(final_png)
  Json::object({
    "target": Json::string(target),
    "initial": initial,
    "pending": pending,
    "success": success,
    "superseded": superseded,
    "canceled": canceled,
    "failed": failed,
    "reset": reset,
    "stopped": stopped,
  }).stringify()
}

///|
#export_name("verify")
pub fn verify(
  page : Page,
  target : String,
  out : String,
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() { verify_checked(page, target, out) })
}
