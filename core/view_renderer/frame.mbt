///|
fn render_item(
  engine : @raster.Engine,
  item : Item,
  theme : @theme.Theme,
) -> Layer {
  let element = item.element
  let bounds = element.bounds
  let inset = theme.spacing.inset
  let line_height = theme.typography.line_height.ceil().to_int()
  let layer = match item.surface {
    Text => {
      let pixels = @raster.render(
        engine,
        element.text,
        bounds.width,
        bounds.height,
        selection=item.selection,
        selection_ranges?=item.selection_ranges,
        caret=item.caret,
        caret_after=item.caret_after,
        single_line_scroll=item.single_line_scroll,
        vertical_scroll=item.vertical_scroll,
        follow_caret=item.follow_caret,
        theme~,
      )
      { bounds, pixels, }
    }
    Control => {
      let label_theme = if item.disabled {
        {
          ..theme,
          foreground: theme.disabled,
          background: theme.disabled_background,
        }
      } else {
        theme
      }
      let label_width = (bounds.width - inset * 2).max(1)
      let label_top = if bounds.height < 36 { 2 } else { 4 }
      let label = @raster.render(
        engine,
        element.text,
        label_width,
        line_height,
        selection=item.selection,
        selection_ranges?=item.selection_ranges,
        caret=item.caret,
        caret_after=item.caret_after,
        single_line_scroll=item.single_line_scroll,
        vertical_scroll=item.vertical_scroll,
        follow_caret=item.follow_caret,
        theme=label_theme,
      )
      let pixels = control_pixels(
        bounds,
        label,
        label_top,
        element.focused,
        disabled=item.disabled,
        theme~,
      )
      { bounds, pixels, }
    }
    Checkbox(checked~, enabled~, invalid~) => {
      let label_width = (bounds.width - inset * 2 - 28).max(1)
      let label_top = if bounds.height < 36 { 2 } else { 4 }
      let label = @raster.render(
        engine,
        element.text,
        label_width,
        line_height,
        theme~,
      )
      let pixels = checkbox_pixels(
        bounds,
        label,
        label_top,
        element.focused,
        checked,
        enabled,
        invalid,
        theme~,
      )
      { bounds, pixels, }
    }
    ListItem(selected~, enabled~) => {
      let label_width = (bounds.width - inset * 2).max(1)
      let label_top = if bounds.height < 36 { 2 } else { 4 }
      let label = @raster.render(
        engine,
        element.text,
        label_width,
        line_height,
        theme~,
      )
      let pixels = list_item_pixels(
        bounds,
        label,
        label_top,
        element.focused,
        selected,
        enabled,
        theme~,
      )
      { bounds, pixels, }
    }
    Status(error~) => {
      let label = @raster.render(
        engine,
        element.text,
        (bounds.width - inset * 2).max(1),
        line_height,
        theme~,
      )
      { bounds, pixels: status_pixels(bounds, label, error, theme~), }
    }
  }
  clip_layer(layer, item.clip)
}

///|
fn status_pixels(
  bounds : @view.Bounds,
  label : Bytes,
  error : Bool,
  theme? : @theme.Theme = @theme.default(),
) -> Bytes {
  let width = bounds.width
  let height = bounds.height
  let inset = theme.spacing.inset
  let label_width = (width - inset * 2).max(1)
  let line_height = theme.typography.line_height.ceil().to_int()
  let rgba = FixedArray::make(width * height * 4, b'\xff')
  let background = if error { theme.error_background } else { theme.status }
  for y in 0..<height {
    for x in 0..<width {
      let offset = (y * width + x) * 4
      rgba[offset] = background.red
      rgba[offset + 1] = background.green
      rgba[offset + 2] = background.blue
    }
  }
  for y in 2..<(height - theme.spacing.border).min(2 + line_height) {
    for x in inset..<(width - inset) {
      let dest = (y * width + x) * 4
      let source = ((y - 2) * label_width + x - inset) * 4
      if label[source] != theme.background.red ||
        label[source + 1] != theme.background.green ||
        label[source + 2] != theme.background.blue {
        for channel in 0..<4 {
          rgba[dest + channel] = label[source + channel]
        }
      }
    }
  }
  rgba.unsafe_reinterpret_as_bytes()
}

///|
fn base_pixels(
  width : Int,
  height : Int,
  color : @theme.Rgb,
) -> FixedArray[Byte] {
  let rgba = FixedArray::make(width * height * 4, b'\xff')
  for index in 0..<(width * height) {
    let offset = index * 4
    rgba[offset] = color.red
    rgba[offset + 1] = color.green
    rgba[offset + 2] = color.blue
  }
  rgba
}

///|
fn list_item_pixels(
  bounds : @view.Bounds,
  label : Bytes,
  label_top : Int,
  focused : Bool,
  selected : Bool,
  enabled : Bool,
  theme? : @theme.Theme = @theme.default(),
) -> Bytes {
  let width = bounds.width
  let height = bounds.height
  let inset = theme.spacing.inset
  let border = theme.spacing.border
  let label_width = (width - inset * 2).max(1)
  let line_height = theme.typography.line_height.ceil().to_int()
  let rgba = base_pixels(width, height, theme.background)
  for y in 0..<height {
    for x in 0..<width {
      let offset = (y * width + x) * 4
      let edge = focused &&
        (
          x < border ||
          x >= width - border ||
          y < border ||
          y >= height - border
        )
      if edge {
        rgba[offset] = theme.focus.red
        rgba[offset + 1] = theme.focus.green
        rgba[offset + 2] = theme.focus.blue
      } else if !enabled {
        rgba[offset] = theme.disabled_background.red
        rgba[offset + 1] = theme.disabled_background.green
        rgba[offset + 2] = theme.disabled_background.blue
      } else if selected {
        rgba[offset] = theme.selected.red
        rgba[offset + 1] = theme.selected.green
        rgba[offset + 2] = theme.selected.blue
      }
    }
  }
  for
    y in label_top.max(border)..<(label_top + line_height).min(height - border) {
    for x in inset..<(width - inset) {
      let dest = (y * width + x) * 4
      let source = ((y - label_top) * label_width + x - inset) * 4
      if label[source] != theme.background.red ||
        label[source + 1] != theme.background.green ||
        label[source + 2] != theme.background.blue {
        for channel in 0..<4 {
          rgba[dest + channel] = label[source + channel]
        }
      }
    }
  }
  rgba.unsafe_reinterpret_as_bytes()
}

///|
fn checkbox_pixels(
  bounds : @view.Bounds,
  label : Bytes,
  label_top : Int,
  focused : Bool,
  checked : Bool,
  enabled : Bool,
  invalid : Bool,
  theme? : @theme.Theme = @theme.default(),
) -> Bytes {
  let width = bounds.width
  let height = bounds.height
  let inset = theme.spacing.inset
  let border = theme.spacing.border
  let line_height = theme.typography.line_height.ceil().to_int()
  let label_width = (width - inset * 2 - 28).max(1)
  let rgba = base_pixels(width, height, theme.background)
  let border_color = if invalid {
    theme.error
  } else if focused {
    theme.focus
  } else {
    theme.border
  }
  let box_y = ((height - 20) / 2).max(border)
  for y in 0..<height {
    for x in 0..<width {
      let index = (y * width + x) * 4
      let outer = x < border ||
        x >= width - border ||
        y < border ||
        y >= height - border
      let bx = x - inset
      let by = y - box_y
      let inside = bx >= 0 && bx < 20 && by >= 0 && by < 20
      let edge = inside &&
        (bx < border || bx >= 20 - border || by < border || by >= 20 - border)
      let mark = checked &&
        inside &&
        (
          (bx >= 5 && bx <= 9 && (by - bx - 5).abs() <= 1) ||
          (bx >= 9 && bx <= 17 && (by + bx - 23).abs() <= 1)
        )
      if outer || edge || mark {
        let color = if !enabled { theme.disabled } else { border_color }
        rgba[index] = color.red
        rgba[index + 1] = color.green
        rgba[index + 2] = color.blue
      }
    }
  }
  for
    y in label_top.max(border)..<(label_top + line_height).min(height - border) {
    for x in (inset + 28)..<(width - inset) {
      let dest = (y * width + x) * 4
      let source = ((y - label_top) * label_width + x - inset - 28) * 4
      for channel in 0..<4 {
        rgba[dest + channel] = label[source + channel]
      }
    }
  }
  rgba.unsafe_reinterpret_as_bytes()
}

///|
fn control_pixels(
  bounds : @view.Bounds,
  label : Bytes,
  label_top : Int,
  focused : Bool,
  disabled? : Bool = false,
  theme? : @theme.Theme = @theme.default(),
) -> Bytes {
  let width = bounds.width
  let height = bounds.height
  let inset = theme.spacing.inset
  let border = theme.spacing.border
  let line_height = theme.typography.line_height.ceil().to_int()
  let label_width = (width - inset * 2).max(1)
  let rgba = base_pixels(
    width,
    height,
    if disabled {
      theme.disabled_background
    } else {
      theme.background
    },
  )
  let border_color = if disabled {
    theme.disabled
  } else if focused {
    theme.focus
  } else {
    theme.border
  }
  for y in 0..<height {
    for x in 0..<width {
      if x < border || x >= width - border || y < border || y >= height - border {
        let offset = (y * width + x) * 4
        rgba[offset] = border_color.red
        rgba[offset + 1] = border_color.green
        rgba[offset + 2] = border_color.blue
      }
    }
  }
  for
    y in label_top.max(border)..<(label_top + line_height).min(height - border) {
    for x in inset..<(width - inset) {
      let dest = (y * width + x) * 4
      let source = ((y - label_top) * label_width + x - inset) * 4
      for channel in 0..<4 {
        rgba[dest + channel] = label[source + channel]
      }
    }
  }
  rgba.unsafe_reinterpret_as_bytes()
}

///|
fn clip_layer(layer : Layer, clip : @view.Bounds?) -> Layer {
  guard clip is Some(clip) else { return layer }
  let bounds = layer.bounds
  let visible = bounds.intersection(clip)
  if visible == Some(bounds) {
    return layer
  }
  guard visible is Some(visible) else {
    return { bounds: { ..clip, width: 0, height: 0, }, pixels: b"", }
  }
  let pixels = Bytes::makei(visible.width * visible.height * 4, index => {
    let x = visible.x - bounds.x + index / 4 % visible.width
    let y = visible.y - bounds.y + index / 4 / visible.width
    layer.pixels[(y * bounds.width + x) * 4 + index % 4]
  })
  { bounds: visible, pixels, }
}

///|
pub fn render(
  engine : @raster.Engine,
  items : Array[Item],
  retain_layout? : Int,
  theme? : @theme.Theme = @theme.default(),
) -> Result[Array[Layer], String] {
  if !theme.valid() {
    return Err("invalid_theme")
  }
  if retain_layout is Some(index) && (index < 0 || index >= items.length()) {
    return Err("invalid_retained_item")
  }
  for item in items {
    let bounds = item.element.bounds
    if bounds.width < 1 ||
      bounds.width > 1024 ||
      bounds.height < 1 ||
      bounds.height > 1024 {
      return Err("invalid_item_bounds")
    }
  }
  let layers : Array[Layer] = items.map(item => {
    bounds: item.element.bounds,
    pixels: b"",
  })
  for index = 0; index < items.length(); index = index + 1 {
    if retain_layout != Some(index) {
      layers[index] = render_item(engine, items[index], theme)
    }
  }
  // Hit testing must retain the requested input, not the last composited label.
  if retain_layout is Some(index) {
    layers[index] = render_item(engine, items[index], theme)
  }
  Ok(layers.filter(layer => layer.bounds.width > 0 && layer.bounds.height > 0))
}
