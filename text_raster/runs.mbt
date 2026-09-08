///|
pub struct TextRun {
  start : Int
  end : Int
  top : Float
  height : Float
  width : Float
  rtl : Bool
}

///|
pub fn text_runs(engine : Engine, committed : String) -> Array[TextRun]? {
  guard engine.text == committed else { return None }
  let buffer = match engine.layout {
    Some(value) => value
    None => return None
  }
  let result : Array[TextRun] = []
  let mut base = 0
  let mut top = 0.0F
  for line in buffer.lines() {
    if base > committed.length() {
      break
    }
    let physical = line
      .layout_runs(None, buffer.metrics().line_height)
      .collect()
    for index in 0..<physical.length() {
      let run = physical[index]
      let mut start = line.text().length()
      for glyph in run.glyphs {
        start = start.min(glyph.start)
      }
      if index == 0 || run.glyphs.is_empty() {
        start = 0
      }
      let mut end = line.text().length() + line.ending().as_str().length()
      if index + 1 < physical.length() {
        end = line.text().length()
        for glyph in physical[index + 1].glyphs {
          end = end.min(glyph.start)
        }
      }
      let first = (base + start).min(committed.length())
      let last = (base + end).min(committed.length())
      if first <= last {
        result.push({
          start: first,
          end: last,
          top: top + run.line_top,
          height: run.line_height,
          width: run.line_w,
          rtl: run.rtl,
        })
      }
    }
    for run in physical {
      top += run.line_height
    }
    base += line.text().length() + line.ending().as_str().length()
  }
  let mut covered = 0
  for run in result {
    guard run.start == covered && run.end >= run.start else { return None }
    covered = run.end
  }
  guard covered == committed.length() && !result.is_empty() else { return None }
  Some(result)
}
