///|
pub(all) enum Surface {
  Text
  Control
} derive(Eq)

///|
pub struct Item {
  element : @view.Element
  surface : Surface
  selection : (Int, Int)
  selection_ranges : Array[(Int, Int)]?
  caret : Int?
  caret_after : Bool
  single_line_scroll : Int?
  vertical_scroll : Int
  follow_caret : Int?
} derive(Eq)

///|
pub fn item(
  element : @view.Element,
  surface? : Surface = Text,
  selection? : (Int, Int) = (0, 0),
  selection_ranges? : Array[(Int, Int)],
  caret? : Int? = None,
  caret_after? : Bool = false,
  single_line_scroll? : Int? = None,
  vertical_scroll? : Int = 0,
  follow_caret? : Int? = None,
) -> Item {
  {
    element,
    surface,
    selection,
    selection_ranges,
    caret,
    caret_after,
    single_line_scroll,
    vertical_scroll,
    follow_caret,
  }
}

///|
pub struct Layer {
  bounds : @view.Bounds
  pixels : Bytes
}
