///|
pub struct TextCell {
  start : Int
  end : Int
  x : Float
  width : Float
}

///|
fn text_cells(
  run : @cosmic.LayoutRun,
  base : Int,
  start : Int,
  end : Int,
  text : String,
) -> Array[TextCell]? {
  let cells : Array[TextCell] = []
  let mut offset = start
  while offset < end {
    let unit = text[offset].to_int()
    let length = if (unit >= 0xD800 && unit <= 0xDBFF) ||
      (unit == 13 && offset + 1 < end && text[offset + 1].to_int() == 10) {
      2
    } else {
      1
    }
    let next = offset + length
    guard next <= end else { return None }
    // A glyph cluster spanning multiple selectable units has no exact subcell contract here.
    for glyph in run.glyphs {
      if (glyph.start < offset - base && offset - base < glyph.end) ||
        (glyph.start < next - base && next - base < glyph.end) {
        return None
      }
    }
    let span = if unit == 13 || unit == 10 {
      Some((if run.rtl { 0.0F } else { run.line_w }, 0.0F))
    } else {
      run.highlight(
        @cosmic.Cursor::new_with_affinity(
          run.line_i,
          offset - base,
          @cosmic.After,
        ),
        @cosmic.Cursor::new_with_affinity(
          run.line_i,
          next - base,
          @cosmic.Before,
        ),
      )
    }
    guard span is Some((x, width)) else { return None }
    cells.push({ start: offset, end: next, x, width, })
    offset = next
  }
  Some(cells)
}
