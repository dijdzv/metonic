///|
extern "C" fn read_line() -> String = "metonic_read_line"

///|
extern "C" fn read_status() -> Int = "metonic_read_status"

///|
#borrow(text)
extern "C" fn write_line(text : String) -> Int = "metonic_write_line"

///|
extern "C" fn capture(
  width : Int,
  height : Int,
  x : Int,
  y : Int,
  w : Int,
  h : Int,
  active : Int,
) -> Int = "metonic_capture"

///|
extern "C" fn finish() -> Unit = "metonic_finish"

///|
struct Request {
  version : Int
  id : Int
  op : String
  x : Int?
  y : Int?
  width : Int?
  height : Int?
  expected_revision : Int?
} derive(FromJson)

///|
struct Response {
  version : Int
  id : Int
  ok : Bool
  error : String?
  state : Array[Int]
  frame : Int
} derive(ToJson)

///|
fn state_snapshot(state : @scene.State) -> Array[Int] {
  [
    @scene.field(state, 0),
    @scene.field(state, 1),
    @scene.field(state, 2),
    @scene.field(state, 3),
    @scene.field(state, 4),
    @scene.field(state, 5),
    @scene.field(state, 6),
    @scene.field(state, 7),
  ]
}

///|
fn response(
  state : @scene.State,
  id : Int,
  ok : Bool,
  error : String?,
  frame : Int,
) -> Response {
  { version: 1, id, ok, error, state: state_snapshot(state), frame, }
}

///|
fn emit(value : Response) -> Bool {
  write_line(@json.to_json(value).stringify()) == 0
}

///|
fn main {
  let state = @scene.create()
  let mut frame = 0
  let mut running = true
  while running {
    let line = read_line()
    let status = read_status()
    if status != 0 {
      if status == 1 {
        running = false
      } else {
        let error = if status == 2 { "line_too_long" } else { "invalid_utf8" }
        if !emit(response(state, -1, false, Some(error), frame)) {
          running = false
        }
      }
      continue
    }
    let parsed = try {
      let req : Request = @json.from_json(@json.parse(line))
      Some(req)
    } catch {
      _ => None
    }
    match parsed {
      None =>
        if !emit(response(state, -1, false, Some("parse_error"), frame)) {
          running = false
        }
      Some(req) => {
        let id = if req.id >= 0 { req.id } else { -1 }
        let mut ok = true
        let mut error : String? = None
        if req.version != 1 {
          ok = false
          error = Some("unsupported_version")
        } else if req.id < 0 {
          ok = false
          error = Some("invalid_id")
        } else if req.expected_revision is Some(expected) &&
          expected != @scene.field(state, 5) {
          ok = false
          error = Some("stale_revision")
        } else {
          match req.op {
            "snapshot" => ()
            "move" =>
              if req.x is Some(x) && req.y is Some(y) {
                ignore(@scene.move_to(state, x, y))
              } else {
                ok = false
                error = Some("missing_argument")
              }
            "resize" =>
              if req.width is Some(width) && req.height is Some(height) {
                if width < 1 || width > 2048 || height < 1 || height > 2048 {
                  ok = false
                  error = Some("invalid_dimensions")
                } else {
                  ignore(@scene.resize(state, width, height))
                }
              } else {
                ok = false
                error = Some("missing_argument")
              }
            "activate" => @scene.activate(state)
            "capture" => {
              let result = capture(
                @scene.field(state, 6),
                @scene.field(state, 7),
                @scene.field(state, 0),
                @scene.field(state, 1),
                @scene.field(state, 2),
                @scene.field(state, 3),
                @scene.field(state, 4),
              )
              if result == 0 {
                frame += 1
              } else {
                ok = false
                error = Some("capture_failed")
              }
            }
            "shutdown" => running = false
            _ => {
              ok = false
              error = Some("unknown_operation")
            }
          }
        }
        if !emit(response(state, id, ok, error, frame)) {
          running = false
        }
      }
    }
  }
  finish()
}
