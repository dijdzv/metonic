///|
pub(all) struct Input {
  reference : @semantics.NodeRef
  single_line : Bool
}

///|
pub(all) struct Preedit {
  reference : @semantics.NodeRef
  text : String
  cursor : Int
  ranges : Array[(Int, Int)]
}

///|
pub struct Presenter {
  priv tree : @semantics.Tree
  priv layouts : @layout.Registry
  priv navigation : @navigation.State
  priv font : Bytes
  priv decoration : @raster.Engine
  priv mut inputs : Array[@semantics.NodeRef]
  priv mut previous : Array[@renderer.Item]?
}

///|
pub fn create(
  tree : @semantics.Tree,
  layouts : @layout.Registry,
  navigation : @navigation.State,
  font : Bytes,
) -> Presenter? {
  @raster.create(font).map(decoration => {
    tree,
    layouts,
    navigation,
    font,
    decoration,
    inputs: [],
    previous: None,
  })
}

///|
fn input_for(inputs : Array[Input], reference : @semantics.NodeRef?) -> Input? {
  guard reference is Some(reference) else { return None }
  for input in inputs {
    if input.reference == reference {
      return Some(input)
    }
  }
  None
}

///|
fn copy_item(item : @renderer.Item, vertical_scroll? : Int) -> @renderer.Item {
  @renderer.item(
    item.element,
    surface=item.surface,
    selection=item.selection,
    selection_ranges?=item.selection_ranges.map(ranges => ranges.copy()),
    caret=item.caret,
    caret_after=item.caret_after,
    single_line_scroll=item.single_line_scroll,
    vertical_scroll=vertical_scroll.unwrap_or(item.vertical_scroll),
    follow_caret=item.follow_caret,
  )
}

///|
pub fn Presenter::render(
  self : Presenter,
  items : Array[@renderer.Item],
  inputs : Array[Input],
  preedit : Preedit?,
) -> Result[Array[@renderer.Layer]?, String] {
  let references : Array[@semantics.NodeRef] = []
  for input in inputs {
    if references.contains(input.reference) {
      return Err("duplicate_input")
    }
    let node = match @semantics.node(self.tree, input.reference) {
      Ok(node) => node
      Err(error) => return Err(error)
    }
    if node.role != @semantics.TextInput {
      return Err("not_input")
    }
    let matching = items.filter(item => {
      item.element.reference == Some(input.reference)
    })
    if matching.length() != 1 {
      return Err("input_item_count")
    }
    references.push(input.reference)
  }
  for item in items {
    let bounds = item.element.bounds
    if bounds.x < 0 ||
      bounds.y < 0 ||
      bounds.width < 1 ||
      bounds.width > 1024 ||
      bounds.height < 1 ||
      bounds.height > 96 {
      return Err("invalid_bounds")
    }
    if item.element.reference is Some(reference) {
      match @semantics.node(self.tree, reference) {
        Ok(node) if node.role == @semantics.TextInput &&
          input_for(inputs, Some(reference)) is None =>
          return Err("input_mode_missing")
        Err(error) => return Err(error)
        _ => ()
      }
    }
  }
  if preedit is Some(value) {
    if !references.contains(value.reference) {
      return Err("preedit_input_missing")
    }
    if value.cursor < 0 || value.cursor > value.text.length() {
      return Err("invalid_preedit_cursor")
    }
    for (start, end) in value.ranges {
      if start < 0 || end < start || end > value.text.length() {
        return Err("invalid_preedit_range")
      }
    }
  }
  for old in self.inputs {
    if !references.contains(old) {
      self.layouts.remove(old)
    }
  }
  for input in inputs {
    if self.layouts.single_line(input.reference) != Some(input.single_line) {
      self.layouts.remove(input.reference)
      if !self.layouts.register(input.reference, self.font, input.single_line) {
        return Err("input_font_unavailable")
      }
      self.previous = None
    }
  }
  self.inputs = references
  let prepared = items.map(item => {
    guard input_for(inputs, item.element.reference) is Some(input) else {
      return copy_item(item)
    }
    let node = @semantics.node(self.tree, input.reference).unwrap()
    let composing = preedit is Some(value) && value.reference == input.reference
    let text = if composing { preedit.unwrap().text } else { node.value }
    let caret = if composing {
      preedit.unwrap().cursor
    } else {
      @semantics.caret(node)
    }
    let selection = if composing {
      (node.selection_start, node.selection_start)
    } else {
      (node.selection_start, node.selection_end)
    }
    let width = if item.surface == @renderer.Control {
      (item.element.bounds.width - 16).max(1)
    } else {
      item.element.bounds.width
    }
    if input.single_line {
      ignore(
        self.layouts.prepare_single_line(
          input.reference,
          text,
          width,
          if node.focused {
            Some(caret)
          } else {
            None
          },
        ),
      )
    }
    @renderer.item(
      { ..item.element, text, focused: node.focused, },
      surface=item.surface,
      selection~,
      selection_ranges?=if composing {
        Some(preedit.unwrap().ranges.copy())
      } else {
        None
      },
      caret=if composing ||
        (node.focused && node.selection_start == node.selection_end) {
        Some(caret)
      } else {
        None
      },
      caret_after=self.navigation.after(
        input.reference,
        caret,
        width,
        preedit is Some(_),
      ),
      single_line_scroll=if input.single_line {
        Some(self.layouts.scroll_x(input.reference))
      } else {
        None
      },
      vertical_scroll=self.layouts.scroll_y(input.reference),
      follow_caret=if input.single_line { None } else { Some(caret) },
    )
  })
  if self.previous == Some(prepared) {
    return Ok(None)
  }
  let layers : Array[@renderer.Layer] = []
  for item in prepared {
    let engine = match input_for(inputs, item.element.reference) {
      Some(input) => self.layouts.engine(input.reference).unwrap()
      None => self.decoration
    }
    match @renderer.render(engine, [item], retain_layout=0) {
      Ok(rendered) => layers.append(rendered)
      Err(error) => return Err(error)
    }
    if input_for(inputs, item.element.reference) is Some(input) &&
      !input.single_line {
      ignore(self.layouts.sync_vertical_scroll(input.reference))
    }
  }
  self.previous = Some(
    prepared.map(item => {
      match input_for(inputs, item.element.reference) {
        Some(input) if !input.single_line =>
          copy_item(
            item,
            vertical_scroll=self.layouts.scroll_y(input.reference),
          )
        _ => copy_item(item)
      }
    }),
  )
  Ok(Some(layers))
}

///|
pub fn Presenter::hit_input(
  self : Presenter,
  reference : @semantics.NodeRef,
  x : Int,
  y : Int,
) -> (Int, Bool)? {
  guard self.previous is Some(items) else { return None }
  guard self.layouts.engine(reference) is Some(engine) else { return None }
  for item in items {
    if item.element.reference != Some(reference) {
      continue
    }
    let left = if item.surface == @renderer.Control { 8 } else { 0 }
    let top = if item.surface == @renderer.Control {
      if item.element.bounds.height < 36 {
        2
      } else {
        4
      }
    } else {
      0
    }
    return @raster.hit_caret(
      engine,
      (x - item.element.bounds.x - left).max(0) +
      self.layouts.scroll_x(reference),
      (y - item.element.bounds.y - top).max(0) +
      self.layouts.scroll_y(reference),
    )
  }
  None
}

///|
pub fn Presenter::input_width(
  self : Presenter,
  reference : @semantics.NodeRef,
) -> Int? {
  guard self.layouts.engine(reference) is Some(_) else { return None }
  guard self.previous is Some(items) else { return None }
  for item in items {
    if item.element.reference == Some(reference) {
      let padding = if item.surface == @renderer.Control { 16 } else { 0 }
      return Some((item.element.bounds.width - padding).max(1))
    }
  }
  None
}

///|
pub fn Presenter::input_text(
  self : Presenter,
  reference : @semantics.NodeRef,
) -> String? {
  guard self.previous is Some(items) else { return None }
  for item in items {
    if item.element.reference == Some(reference) {
      return Some(item.element.text)
    }
  }
  None
}

///|
pub fn Presenter::active_caret(
  self : Presenter,
  reference : @semantics.NodeRef,
) -> Int? {
  guard self.previous is Some(items) else { return None }
  let node = match @semantics.node(self.tree, reference) {
    Ok(node) => node
    Err(_) => return None
  }
  for item in items {
    if item.element.reference == Some(reference) {
      return Some(
        item.follow_caret.unwrap_or_else(() => {
          item.caret.unwrap_or_else(() => @semantics.caret(node))
        }),
      )
    }
  }
  None
}

///|
pub fn Presenter::caret_position(
  self : Presenter,
  reference : @semantics.NodeRef,
) -> (Int, Int)? {
  guard self.previous is Some(items) else { return None }
  guard self.layouts.engine(reference) is Some(engine) else { return None }
  let node = match @semantics.node(self.tree, reference) {
    Ok(node) => node
    Err(_) => return None
  }
  for item in items {
    if item.element.reference != Some(reference) {
      continue
    }
    let caret = item.caret.unwrap_or_else(() => @semantics.caret(node))
    guard @raster.caret_position(engine, caret, after=item.caret_after)
      is Some((x, y)) else {
      return None
    }
    let left = if item.surface == @renderer.Control { 8 } else { 0 }
    let top = if item.surface == @renderer.Control {
      if item.element.bounds.height < 36 {
        2
      } else {
        4
      }
    } else {
      0
    }
    return Some(
      (
        item.element.bounds.x + left + x - self.layouts.scroll_x(reference),
        item.element.bounds.y + top + y - self.layouts.scroll_y(reference),
      ),
    )
  }
  None
}
