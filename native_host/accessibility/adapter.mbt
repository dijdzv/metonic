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
extern "C" fn node_new(role : Int) -> UInt64 = "accesskit_node_new"

///|
extern "C" fn push_child(node : UInt64, child : UInt64) -> Unit = "accesskit_node_push_child"

///|
extern "C" fn add_action(node : UInt64, action : Int) -> Unit = "accesskit_node_add_action"

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
pub struct Bridge {
  mut adapter : UInt64
  mut nodes : Array[@semantics.Node]
  mut width : Int
  mut height : Int
  mut x : Int
  mut y : Int
}

///|
// The native event-loop library permits one active UI loop per process.
let current : Ref[Bridge?] = { val: None, }

///|
fn tree(_data : UInt64) -> UInt64 {
  let bridge = current.val.unwrap()
  let root = node_new(114)
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
      toggled(node, if semantic.value == "on" { 1 } else { 0 })
      bounds(node, bridge.x.to_double(), bridge.y.to_double(), 120, 72)
    } else {
      // Value editing is not advertised until its action/selection mapping exists.
      read_only(node)
      bounds(node, 8, 8, (bridge.width - 16).max(1).min(640).to_double(), 96)
    }
    push_child(root, id)
    push_node(result, id, node)
  }
  push_node(result, 0UL, root)
  result
}

///|
pub fn open(hwnd : UInt64, nodes : Array[@semantics.Node]) -> Bridge? {
  guard current.val is None else { return None }
  let bridge = Bridge::{
    adapter: 0UL,
    nodes,
    width: 640,
    height: 360,
    x: 260,
    y: 144,
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
) -> Unit {
  if self.adapter == 0UL {
    return
  }
  self.nodes = nodes
  self.width = width
  self.height = height
  self.x = x
  self.y = y
  let events = update_active(self.adapter, data => tree(data), 0UL)
  if events != 0UL {
    raise_events(events)
  }
}

///|
pub fn Bridge::poll(self : Bridge) -> Array[(Int, Int)] {
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
    if id == 1UL || id == 2UL {
      result.push((action(request), id.to_int()))
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
