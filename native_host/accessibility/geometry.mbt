///|
#borrow(values)
extern "C" fn character_positions(
  node : UInt64,
  count : UInt64,
  values : FixedArray[Float],
) -> Unit = "accesskit_node_set_character_positions"

///|
#borrow(values)
extern "C" fn character_widths(
  node : UInt64,
  count : UInt64,
  values : FixedArray[Float],
) -> Unit = "accesskit_node_set_character_widths"

///|
extern "C" fn text_direction(node : UInt64, direction : Byte) -> Unit = "accesskit_node_set_text_direction"

///|
extern "C" fn clips_children(node : UInt64) -> Unit = "accesskit_node_set_clips_children"

///|
fn publish_geometry(node : UInt64, fragment : TextFragment) -> Unit {
  text_direction(node, if fragment.layout.rtl { b'\x01' } else { b'\x00' })
  guard fragment.layout.cells is Some(cells) else { return }
  guard cells.length() == fragment.units.lengths.length() else { return }
  for index in 0..<cells.length() {
    guard cells[index].start - fragment.layout.start ==
      fragment.units.offsets[index] &&
      cells[index].end - fragment.layout.start ==
      fragment.units.offsets[index + 1] else {
      return
    }
  }
  character_positions(
    node,
    cells.length().to_uint64(),
    FixedArray::makei(cells.length(), i => {
      if fragment.layout.rtl {
        fragment.layout.width - cells[i].x - cells[i].width
      } else {
        cells[i].x
      }
    }),
  )
  character_widths(
    node,
    cells.length().to_uint64(),
    FixedArray::makei(cells.length(), i => cells[i].width),
  )
}
