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
struct NodeTarget {
  session : Int
  window : Int
  id : Int
  generation : Int
} derive(FromJson)

///|
struct NodeDto {
  session : Int
  window : Int
  id : Int
  generation : Int
  role : String
  name : String
  value : String
  enabled : Bool
  focused : Bool
  selection_start : Int
  selection_end : Int
} derive(ToJson)

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
  node : NodeTarget?
  text : String?
  start : Int?
  end : Int?
  enabled : Bool?
  expected_semantic_revision : Int?
} derive(FromJson)

///|
fn node_ref(target : NodeTarget) -> @semantics.NodeRef {
  {
    session: target.session,
    window: target.window,
    id: target.id,
    generation: target.generation,
  }
}

///|
fn semantic_nodes(tree : @semantics.Tree) -> Array[NodeDto] {
  @semantics.snapshot(tree).map(fn(node) {
    let role = match node.role {
      @semantics.Role::Button => "button"
      @semantics.Role::TextInput => "text_input"
    }
    {
      session: node.reference.session,
      window: node.reference.window,
      id: node.reference.id,
      generation: node.reference.generation,
      role,
      name: node.name,
      value: node.value,
      enabled: node.enabled,
      focused: node.focused,
      selection_start: node.selection_start,
      selection_end: node.selection_end,
    }
  })
}

///|
fn activate_button(tree : @semantics.Tree, state : @scene.State) -> String {
  for node in @semantics.snapshot(tree) {
    if node.role is @semantics.Role::Button {
      if !node.enabled {
        return "disabled"
      }
      let result = @semantics.activate(tree, node.reference)
      if result == "" {
        @scene.activate(state)
      }
      return result
    }
  }
  "missing_argument"
}

///|
fn semantic_dispatch(
  tree : @semantics.Tree,
  state : @scene.State,
  req : Request,
) -> String {
  if req.op == "semantic_recreate_input" {
    return match @semantics.recreate_input(tree) {
      Some(_) => ""
      None => "unavailable"
    }
  }
  if req.op == "semantic_snapshot" {
    return ""
  }
  if req.op != "semantic_activate" &&
    req.op != "semantic_focus" &&
    req.op != "semantic_set_text" &&
    req.op != "semantic_set_selection" &&
    req.op != "semantic_set_enabled" &&
    req.op != "semantic_remove" {
    return "unknown_operation"
  }
  let target = match req.node {
    Some(value) => value
    None => return "missing_argument"
  }
  let reference = node_ref(target)
  match req.op {
    "semantic_activate" => {
      let result = @semantics.activate(tree, reference)
      if result == "" {
        @scene.activate(state)
      }
      result
    }
    "semantic_focus" => @semantics.focus(tree, reference)
    "semantic_set_text" =>
      match req.text {
        Some(value) => @semantics.set_text(tree, reference, value)
        None => "missing_argument"
      }
    "semantic_set_selection" =>
      match (req.start, req.end) {
        (Some(start), Some(end)) =>
          @semantics.set_selection(tree, reference, start, end)
        _ => "missing_argument"
      }
    "semantic_set_enabled" =>
      match req.enabled {
        Some(value) => @semantics.set_enabled(tree, reference, value)
        None => "missing_argument"
      }
    "semantic_remove" => @semantics.remove(tree, reference)
    _ => "unknown_operation"
  }
}

///|
struct Response {
  version : Int
  id : Int
  ok : Bool
  error : String?
  state : Array[Int]
  frame : Int
  semantic_revision : Int
  nodes : Array[NodeDto]
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
  tree : @semantics.Tree,
  id : Int,
  ok : Bool,
  error : String?,
  frame : Int,
) -> Response {
  {
    version: 1,
    id,
    ok,
    error,
    state: state_snapshot(state),
    frame,
    semantic_revision: @semantics.revision(tree),
    nodes: semantic_nodes(tree),
  }
}

///|
fn emit(value : Response) -> Bool {
  write_line(@json.to_json(value).stringify()) == 0
}

///|
fn main {
  let state = @scene.create()
  let tree = @semantics.create(1, 1)
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
        if !emit(response(state, tree, -1, false, Some(error), frame)) {
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
        if !emit(response(state, tree, -1, false, Some("parse_error"), frame)) {
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
        } else if req.expected_semantic_revision is Some(expected) &&
          expected != @semantics.revision(tree) {
          ok = false
          error = Some("stale_semantic_revision")
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
            "activate" => {
              let result = activate_button(tree, state)
              if result != "" {
                ok = false
                error = Some(result)
              }
            }
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
              let semantic_error = semantic_dispatch(tree, state, req)
              if semantic_error != "" {
                ok = false
                error = Some(semantic_error)
              }
            }
          }
        }
        if !emit(response(state, tree, id, ok, error, frame)) {
          running = false
        }
      }
    }
  }
  ignore(@semantics.dispose(tree))
  finish()
}
