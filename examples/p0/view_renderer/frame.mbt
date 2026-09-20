///|
pub using @renderer {type Layer}

///|
pub fn render(
  engine : @raster.Engine,
  view : @application.View,
  text : String,
  selection? : (Int, Int) = (0, 0),
  selection_ranges? : Array[(Int, Int)],
  query_selection_ranges? : Array[(Int, Int)],
  caret? : Int? = None,
  caret_after? : Bool = false,
  query_scroll? : Int? = None,
  editor_scroll? : Int = 0,
  editor_active_caret? : Int? = None,
) -> Array[Layer] {
  @renderer.render(
    engine,
    items(
      view,
      text,
      selection~,
      selection_ranges?,
      query_selection_ranges?,
      caret~,
      caret_after~,
      query_scroll~,
      editor_scroll~,
      editor_active_caret~,
    ),
    retain_layout=0,
  ).unwrap()
}

///|
pub fn items(
  view : @application.View,
  text : String,
  selection? : (Int, Int) = (0, 0),
  selection_ranges? : Array[(Int, Int)],
  query_selection_ranges? : Array[(Int, Int)],
  caret? : Int? = None,
  caret_after? : Bool = false,
  query_scroll? : Int? = None,
  editor_scroll? : Int = 0,
  editor_active_caret? : Int? = None,
) -> Array[@renderer.Item] {
  let items = [
    @renderer.item(
      { ..view.editor, text, },
      selection~,
      selection_ranges?,
      caret~,
      caret_after~,
      vertical_scroll=editor_scroll,
      follow_caret=editor_active_caret,
    ),
    @renderer.item(view.request, surface=Control),
  ]
  if view.result.text != "" {
    items.push(@renderer.item(view.result))
  }
  items.push(@renderer.item(view.task_status))
  items.push(@renderer.item(view.start, surface=Control))
  items.push(@renderer.item(view.cancel, surface=Control))
  items.push(@renderer.item(view.query_label))
  items.push(
    @renderer.item(
      view.query,
      surface=Control,
      selection=view.query_selection,
      selection_ranges?=query_selection_ranges,
      caret=view.query_caret,
      single_line_scroll=query_scroll,
    ),
  )
  items
}
