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
extern "C" fn invalid(node : UInt64, value : Int) -> Unit = "accesskit_node_set_invalid"

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
  priv mut presentation : Presentation
  priv mut adapter : UInt64
  priv mut nodes : Array[@semantics.Node]
  priv mut fragments : Array[TextFragment]
  priv mut layout : Array[@raster.TextRun]?
  priv mut next_text_id : UInt64
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
  let title = @utf8.encode(bridge.presentation.title)
  label(root, title, title.length().to_uint64())
  bounds(
    root,
    0,
    0,
    bridge.presentation.width.to_double(),
    bridge.presentation.height.to_double(),
  )
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
    let presentation = bridge.presentation.control(semantic.reference).unwrap()
    let box = presentation.bounds
    let node = node_new(
      match semantic.role {
        @semantics.Label => 3
        @semantics.Button => 18
        @semantics.Checkbox => 15
        @semantics.TextInput => 17
      },
    )
    let name = @utf8.encode(semantic.name)
    label(node, name, name.length().to_uint64())
    let text = @utf8.encode(semantic.value)
    value(node, text, text.length().to_uint64())
    if !semantic.enabled {
      disabled(node)
    }
    if semantic.invalid {
      invalid(node, 0)
    }
    if semantic.role != @semantics.Label {
      add_action(node, 1)
    }
    bounds(
      node,
      box.x.to_double(),
      box.y.to_double(),
      box.width.to_double(),
      box.height.to_double(),
    )
    if semantic.role is @semantics.Button ||
      semantic.role is @semantics.Checkbox {
      add_action(node, 0)
      if semantic.role is @semantics.Checkbox {
        toggled(node, if semantic.checked { 1 } else { 0 })
      } else if presentation.toggled is Some(active) {
        toggled(node, if active { 1 } else { 0 })
      }
    } else if bridge.presentation.text_owner == Some(semantic.reference) {
      if bridge.presentation.composing || semantic.read_only {
        read_only(node)
      } else {
        add_value_action(node)
      }
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
          box.y.to_double() +
          fragment.layout.top.to_double() -
          bridge.presentation.text_scroll.to_double(),
          fragment.layout.width.to_double(),
          fragment.layout.height.to_double(),
        )
        push_child(node, fragment.id)
        push_node(result, fragment.id, run)
      }
      if !bridge.presentation.composing {
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
    if semantic.role is @semantics.TextInput &&
      bridge.presentation.text_owner != Some(semantic.reference) {
      if semantic.read_only {
        read_only(node)
      } else {
        add_value_action(node)
      }
    }
    push_child(root, id)
    push_node(result, id, node)
  }
  for item in bridge.presentation.statuses {
    let status = node_new(3)
    let text = @utf8.encode(item.text)
    value(status, text, text.length().to_uint64())
    let box = item.bounds
    bounds(
      status,
      box.x.to_double(),
      box.y.to_double(),
      box.width.to_double(),
      box.height.to_double(),
    )
    push_child(root, item.id)
    push_node(result, item.id, status)
  }
  push_node(result, 0UL, root)
  result
}

///|
pub fn open(
  hwnd : UInt64,
  nodes : Array[@semantics.Node],
  presentation : Presentation,
) -> Bridge? {
  guard current.val is None && valid_presentation(nodes, presentation) else {
    return None
  }
  let bridge = Bridge::{
    adapter: 0UL,
    presentation: presentation.snapshot(),
    nodes: nodes.copy(),
    fragments: [],
    layout: None,
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
fn Bridge::replace_snapshot(
  self : Bridge,
  nodes : Array[@semantics.Node],
  presentation : Presentation,
  layout : Array[@raster.TextRun]?,
) -> Bool {
  guard valid_presentation(nodes, presentation) else { return false }
  let layout = layout.map(runs => runs.map(run => run.copy()))
  let owner = owner_node(nodes, presentation.text_owner)
  let old_owner = owner_node(self.nodes, self.presentation.text_owner)
  if layout is Some(runs) {
    guard owner is Some(node) else { return false }
    for run in runs {
      if run.start < 0 ||
        run.end < run.start ||
        run.end > node.value.length() ||
        @position.utf16_to_scalar(node.value, run.start) is None ||
        @position.utf16_to_scalar(node.value, run.end) is None {
        return false
      }
    }
  }
  if layout is None {
    self.fragments = []
  } else if self.fragments.is_empty() ||
    self.presentation.text_owner != presentation.text_owner ||
    old_owner.map(node => node.value) != owner.map(node => node.value) ||
    self.layout != layout {
    let text = owner.unwrap().value
    let fragments : Array[TextFragment] = []
    for run in layout.unwrap() {
      let part = text[run.start:run.end].to_owned()
      guard text_units(part) is Some(units) else { return false }
      fragments.push({ id: self.next_text_id, layout: run, text: part, units, })
      self.next_text_id += 1UL
    }
    self.fragments = fragments
  }
  self.presentation = presentation.snapshot()
  self.nodes = nodes.copy()
  self.layout = layout.map(runs => runs.copy())
  true
}

///|
pub fn Bridge::update(
  self : Bridge,
  nodes : Array[@semantics.Node],
  presentation : Presentation,
  layout : Array[@raster.TextRun]?,
) -> Bool {
  guard self.adapter != 0UL &&
    self.replace_snapshot(nodes, presentation, layout) else {
    return false
  }
  let events = update_active(self.adapter, data => tree(data), 0UL)
  if events != 0UL {
    raise_events(events)
  }
  true
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
        3 if self.presentation.text_owner.map(reference => {
            reference.id.to_uint64()
          }) ==
          Some(id) =>
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
pub fn Bridge::fragment_ids(self : Bridge) -> Array[UInt64] {
  self.fragments.map(fragment => fragment.id)
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
