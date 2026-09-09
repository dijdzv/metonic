///|
extern "C" fn native_open(
  hwnd : UInt64,
  activate : FuncRef[(UInt64) -> UInt64],
) -> UInt64 = "metonic_accesskit_open"

///|
extern "C" fn native_close(adapter : UInt64) -> Unit = "metonic_accesskit_close"

///|
extern "C" fn take() -> UInt64 = "metonic_accesskit_take"

///|
extern "C" fn action(request : UInt64) -> Int = "metonic_accesskit_action"

///|
extern "C" fn target(request : UInt64) -> UInt64 = "metonic_accesskit_node"

///|
extern "C" fn free_request(request : UInt64) -> Unit = "accesskit_action_request_free"

///|
extern "C" fn value_length(request : UInt64) -> Int = "metonic_accesskit_value_length"

///|
#borrow(output)
extern "C" fn copy_value(
  request : UInt64,
  output : FixedArray[Byte],
  capacity : Int,
) -> Int = "metonic_accesskit_copy_value"

///|
extern "C" fn node_new(role : Int) -> UInt64 = "accesskit_node_new"

///|
extern "C" fn push_child(node : UInt64, child : UInt64) -> Unit = "accesskit_node_push_child"

///|
extern "C" fn add_action(node : UInt64, action : Int) -> Unit = "accesskit_node_add_action"

///|
extern "C" fn add_value_action(node : UInt64) -> Unit = "metonic_accesskit_value_action"

///|
extern "C" fn disabled(node : UInt64) -> Unit = "accesskit_node_set_disabled"

///|
extern "C" fn read_only(node : UInt64) -> Unit = "accesskit_node_set_read_only"

///|
extern "C" fn toggled(node : UInt64, value : Int) -> Unit = "accesskit_node_set_toggled"

///|
extern "C" fn bounds(
  node : UInt64,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> Unit = "metonic_accesskit_bounds"

///|
#borrow(value)
extern "C" fn label(node : UInt64, value : Bytes, length : UInt64) -> Unit = "accesskit_node_set_label_with_length"

///|
#borrow(value)
extern "C" fn value(node : UInt64, value : Bytes, length : UInt64) -> Unit = "accesskit_node_set_value_with_length"

///|
extern "C" fn tree_new(root : UInt64) -> UInt64 = "accesskit_tree_new"

///|
extern "C" fn update_new(focus : UInt64) -> UInt64 = "accesskit_tree_update_with_focus"

///|
extern "C" fn set_tree(update : UInt64, tree : UInt64) -> Unit = "accesskit_tree_update_set_tree"

///|
extern "C" fn push_node(update : UInt64, id : UInt64, node : UInt64) -> Unit = "accesskit_tree_update_push_node"

///|
extern "C" fn update_active(
  adapter : UInt64,
  factory : FuncRef[(UInt64) -> UInt64],
  data : UInt64,
) -> UInt64 = "accesskit_windows_subclassing_adapter_update_if_active"

///|
extern "C" fn raise_events(events : UInt64) -> Unit = "accesskit_windows_queued_events_raise"

///|
#borrow(lengths)
extern "C" fn character_lengths(
  node : UInt64,
  count : UInt64,
  lengths : Bytes,
) -> Unit = "accesskit_node_set_character_lengths"

///|
pub struct TextFragment {
  id : UInt64
  layout : @raster.TextRun
  text : String
  units : TextUnits
}

///|
pub struct Bridge {
  mut view : @application.View
  mut adapter : UInt64
  mut nodes : Array[@semantics.Node]
  mut width : Int
  mut height : Int
  mut x : Int
  mut y : Int
  mut composing : Bool
  mut rpc_result : String
  mut fragments : Array[TextFragment]
  mut next_text_id : UInt64
}

///|
pub(all) enum Request {
  Click(Int)
  Focus(Int)
  SetValue(Int, String)
  Select(UInt64, UInt64, UInt64, UInt64)
}

///|
// The native event-loop library permits one active UI loop per process.
let current : Ref[Bridge?] = { val: None, }

///|
fn tree(_data : UInt64) -> UInt64 {
  let bridge = current.val.unwrap()
  let root = node_new(133)
  label(root, b"Metonic", 7UL)
  bounds(root, 0, 0, bridge.width.to_double(), bridge.height.to_double())
  let mut focus = 0UL
  for node in bridge.nodes {
    if node.focused {
      focus = node.reference.id.to_uint64()
    }
  }
  let result = update_new(focus)
  set_tree(result, tree_new(0UL))
  for semantic in bridge.nodes {
    let id = semantic.reference.id.to_uint64()
    let node = node_new(
      if semantic.role is @semantics.Button {
        18
      } else {
        17
      },
    )
    let name = @utf8.encode(semantic.name)
    label(node, name, name.length().to_uint64())
    let text = @utf8.encode(semantic.value)
    value(node, text, text.length().to_uint64())
    if !semantic.enabled {
      disabled(node)
    }
    add_action(node, 1)
    if semantic.role is @semantics.Button {
      add_action(node, 0)
      if id == 1UL {
        toggled(node, if semantic.value == "on" { 1 } else { 0 })
        bounds(node, bridge.x.to_double(), bridge.y.to_double(), 120, 72)
      } else {
        let box = if bridge.view.start.reference is Some(reference) &&
          reference.id.to_uint64() == id {
          bridge.view.start.bounds
        } else if bridge.view.cancel.reference is Some(reference) &&
          reference.id.to_uint64() == id {
          bridge.view.cancel.bounds
        } else {
          bridge.view.request.bounds
        }
        bounds(
          node,
          box.x.to_double(),
          box.y.to_double(),
          box.width.to_double(),
          box.height.to_double(),
        )
      }
    } else if id == 2UL {
      if bridge.composing {
        read_only(node)
      } else {
        add_value_action(node)
      }
      let box = bridge.view.editor.bounds
      bounds(
        node,
        box.x.to_double(),
        box.y.to_double(),
        box.width.to_double(),
        box.height.to_double(),
      )
      clips_children(node)
      for fragment in bridge.fragments {
        let run = node_new(1)
        let text = @utf8.encode(fragment.text)
        value(run, text, text.length().to_uint64())
        character_lengths(
          run,
          fragment.units.lengths.length().to_uint64(),
          fragment.units.lengths,
        )
        publish_geometry(run, fragment)
        bounds(
          run,
          box.x.to_double(),
          box.y.to_double() + fragment.layout.top.to_double(),
          fragment.layout.width.to_double(),
          fragment.layout.height.to_double(),
        )
        push_child(node, fragment.id)
        push_node(result, fragment.id, run)
      }
      if !bridge.composing {
        match
          (
            bridge.text_position(semantic.selection_anchor),
            bridge.text_position(@semantics.caret(semantic)),
          ) {
          (Some((anchor_node, anchor_index)), Some((focus_node, focus_index))) =>
            publish_selection(
              node, anchor_node, anchor_index, focus_node, focus_index,
            )
          _ => ()
        }
      }
    }
    if semantic.role is @semantics.TextInput && id != 2UL {
      add_value_action(node)
      let box = bridge.view.query.bounds
      bounds(
        node,
        box.x.to_double(),
        box.y.to_double(),
        box.width.to_double(),
        box.height.to_double(),
      )
    }
    push_child(root, id)
    push_node(result, id, node)
  }
  if bridge.rpc_result != "" {
    let status = node_new(3)
    let text = @utf8.encode(bridge.rpc_result.trim().to_owned())
    value(status, text, text.length().to_uint64())
    let box = bridge.view.result.bounds
    bounds(
      status,
      box.x.to_double(),
      box.y.to_double(),
      box.width.to_double(),
      box.height.to_double(),
    )
    push_child(root, 4294967295UL)
    push_node(result, 4294967295UL, status)
  }
  let task_status = node_new(3)
  let task_text = @utf8.encode(bridge.view.task_status.text)
  value(task_status, task_text, task_text.length().to_uint64())
  let task_box = bridge.view.task_status.bounds
  bounds(
    task_status,
    task_box.x.to_double(),
    task_box.y.to_double(),
    task_box.width.to_double(),
    task_box.height.to_double(),
  )
  push_child(root, 4294967294UL)
  push_node(result, 4294967294UL, task_status)
  push_node(result, 0UL, root)
  result
}

///|
pub fn open(
  hwnd : UInt64,
  nodes : Array[@semantics.Node],
  view : @application.View,
) -> Bridge? {
  guard current.val is None else { return None }
  let bridge = Bridge::{
    adapter: 0UL,
    view,
    nodes,
    width: 640,
    height: 360,
    x: 260,
    y: 144,
    composing: false,
    rpc_result: "",
    fragments: [],
    next_text_id: 4294967296UL,
  }
  current.val = Some(bridge)
  bridge.adapter = native_open(hwnd, data => tree(data))
  if bridge.adapter == 0UL {
    current.val = None
    None
  } else {
    Some(bridge)
  }
}

///|
pub fn Bridge::update(
  self : Bridge,
  nodes : Array[@semantics.Node],
  width : Int,
  height : Int,
  x : Int,
  y : Int,
  composing : Bool,
  rpc_result : String,
  layout : Array[@raster.TextRun]?,
  view : @application.View,
) -> Unit {
  if self.adapter == 0UL {
    return
  }
  if layout is None {
    self.fragments = []
  } else if self.fragments.is_empty() ||
    self.nodes[1].value != nodes[1].value ||
    self.width != width {
    let text = nodes[1].value
    let fragments : Array[TextFragment] = []
    for run in layout.unwrap() {
      let part = text[run.start:run.end].to_owned()
      guard text_units(part) is Some(units) else {
        fragments.clear()
        break
      }
      fragments.push({ id: self.next_text_id, layout: run, text: part, units, })
      self.next_text_id += 1UL
    }
    self.fragments = fragments
  }
  self.view = view
  self.nodes = nodes
  self.width = width
  self.height = height
  self.x = x
  self.y = y
  self.composing = composing
  self.rpc_result = rpc_result
  let events = update_active(self.adapter, data => tree(data), 0UL)
  if events != 0UL {
    raise_events(events)
  }
}

///|
pub fn Bridge::poll(self : Bridge) -> Array[Request] {
  let result = []
  if self.adapter == 0UL {
    return result
  }
  for _ in 0..<32 {
    let request = take()
    if request == 0UL {
      break
    }
    let id = target(request)
    if bridge_node_exists(self.nodes, id) {
      match action(request) {
        0 => result.push(Click(id.to_int()))
        1 => result.push(Focus(id.to_int()))
        2 if self.nodes.any(node => {
            node.reference.id.to_uint64() == id &&
            node.role is @semantics.TextInput
          }) => {
          let length = value_length(request)
          if length >= 0 && length <= 65536 {
            let bytes = FixedArray::make(length, b'\x00')
            if copy_value(request, bytes, length) != 0 {
              try @utf8.decode(bytes.unsafe_reinterpret_as_bytes()) catch {
                _ => ()
              } noraise {
                text => result.push(SetValue(id.to_int(), text))
              }
            }
          }
        }
        3 if id == 2UL =>
          result.push(
            Select(
              selection_field(request, 0),
              selection_field(request, 1),
              selection_field(request, 2),
              selection_field(request, 3),
            ),
          )
        _ => ()
      }
    }
    free_request(request)
  }
  result
}

///|
pub fn Bridge::close(self : Bridge) -> Unit {
  if self.adapter != 0UL {
    native_close(self.adapter)
    self.adapter = 0UL
    current.val = None
  }
}

///|
fn bridge_node_exists(nodes : Array[@semantics.Node], id : UInt64) -> Bool {
  for node in nodes {
    if node.reference.id.to_uint64() == id {
      return true
    }
  }
  false
}
