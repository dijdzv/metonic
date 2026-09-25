///|
pub struct Widget {
  priv reference : @semantics.NodeRef
  priv render : (@view.Bounds, @view.Bounds?) -> Control
}

///|
pub fn Widget::button(value : @component.UiButton) -> Widget {
  {
    reference: value.reference(),
    render: (bounds, clip) => button(value, bounds, clip~),
  }
}

///|
pub fn Widget::checkbox(value : @component.UiCheckbox) -> Widget {
  {
    reference: value.reference(),
    render: (bounds, clip) => checkbox(value, bounds, clip~),
  }
}

///|
pub fn Widget::label(value : @component.UiLabel) -> Widget {
  {
    reference: value.reference(),
    render: (bounds, clip) => label(value, bounds, clip~),
  }
}

///|
pub fn Widget::input(value : @component.UiInput) -> Widget {
  {
    reference: value.reference(),
    render: (bounds, clip) => input(value, bounds, clip~),
  }
}

///|
pub fn Widget::custom(
  reference : @semantics.NodeRef,
  render : (@view.Bounds, @view.Bounds?) -> Control,
) -> Widget {
  { reference, render, }
}

///|
pub fn Widget::reference(self : Widget) -> @semantics.NodeRef {
  self.reference
}

///|
pub struct StackItem {
  priv track : @layout.Track
  priv widget : Widget
}

///|
pub fn StackItem::new(track : @layout.Track, widget : Widget) -> StackItem {
  { track, widget, }
}

///|
pub struct Stack {
  axis : @layout.Axis
  gap : Int
  padding : @layout.Padding
}

///|
pub fn Stack::new(
  axis : @layout.Axis,
  gap? : Int = 0,
  padding? : @layout.Padding = { top: 0, right: 0, bottom: 0, left: 0, },
) -> Stack {
  { axis, gap, padding, }
}

///|
pub fn Stack::arrange(
  self : Stack,
  bounds : @view.Bounds,
  children : Array[StackItem],
  clip? : @view.Bounds? = None,
) -> Result[Array[Control], String] {
  match
    @layout.layout_linear(
      axis=self.axis,
      bounds~,
      tracks=children.map(child => child.track),
      gap=self.gap,
      padding=self.padding,
    ) {
    Err(error) => Err(error)
    Ok(placements) => {
      let controls : Array[Control] = []
      for index, child in children {
        let control = (child.widget.render)(placements[index], clip)
        if control.element.reference != Some(child.widget.reference) {
          return Err("layout_reference_mismatch")
        }
        controls.push(control)
      }
      Ok(controls)
    }
  }
}

///|
pub struct ScrollView {
  list : @layout.VerticalList
}

///|
pub struct ScrollItem {
  priv height : Int
  priv widget : Widget
}

///|
pub fn ScrollItem::new(height : Int, widget : Widget) -> ScrollItem {
  { height, widget, }
}

///|
pub fn ScrollView::new(gap? : Int = 0) -> Result[ScrollView, String] {
  match @layout.VerticalList::new(row_height=1, gap~) {
    Err(error) => Err(error)
    Ok(list) => Ok({ list, })
  }
}

///|
pub fn ScrollView::arrange(
  self : ScrollView,
  bounds : @view.Bounds,
  children : Array[ScrollItem],
) -> Result[Array[Control], String] {
  match
    self.list.arrange_heights(
      bounds,
      children.map(child => child.widget.reference),
      children.map(child => child.height),
    ) {
    Err(error) => Err(error)
    Ok(_) => {
      let controls : Array[Control] = []
      for index, placement in self.list.items() {
        let widget = children[index].widget
        let control = (widget.render)(placement.bounds, Some(bounds))
        if control.element.reference != Some(widget.reference) {
          return Err("layout_reference_mismatch")
        }
        controls.push(control)
      }
      Ok(controls)
    }
  }
}

///|
pub fn ScrollView::viewport(self : ScrollView) -> Viewport {
  {
    scroll: (x, y, pixels) => self.list.scroll_at(x, y, pixels),
    reveal: reference => self.list.reveal(reference),
  }
}
