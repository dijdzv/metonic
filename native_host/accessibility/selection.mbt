///|
extern "C" fn selection_field(request : UInt64, field : Int) -> UInt64 = "metonic_accesskit_selection_field"

///|
extern "C" fn publish_selection(
  node : UInt64,
  anchor_node : UInt64,
  anchor_index : UInt64,
  focus_node : UInt64,
  focus_index : UInt64,
) -> Unit = "metonic_accesskit_selection"

///|
fn Bridge::text_position(self : Bridge, offset : Int) -> (UInt64, UInt64)? {
  for fragment in self.fragments {
    if offset >= fragment.layout.start && offset <= fragment.layout.end {
      if fragment.units.character_at(offset - fragment.layout.start)
        is Some(index) {
        return Some((fragment.id, index.to_uint64()))
      }
    }
  }
  None
}

///|
fn Bridge::text_offset(self : Bridge, node : UInt64, index : UInt64) -> Int? {
  for fragment in self.fragments {
    if fragment.id == node &&
      index < fragment.units.offsets.length().to_uint64() {
      return fragment.units
        .utf16_at(index.to_int())
        .map(offset => fragment.layout.start + offset)
    }
  }
  None
}

///|
pub fn Bridge::resolve_selection(
  self : Bridge,
  request : Request,
) -> (Int, Int)? {
  guard !self.composing && self.adapter != 0UL else { return None }
  guard request is Select(anchor_node, anchor_index, focus_node, focus_index) else {
    return None
  }
  match
    (
      self.text_offset(anchor_node, anchor_index),
      self.text_offset(focus_node, focus_index),
    ) {
    (Some(anchor), Some(focus)) => Some((anchor, focus))
    _ => None
  }
}
