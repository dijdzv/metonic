///|
priv struct CollectionLayout {
  editor : @view.Bounds
  list : @view.Bounds
  actions : Array[@view.Bounds]
  search : @view.Bounds
  search_label : @view.Bounds
  status : @view.Bounds
}

///|
fn collection_layout(width : Int, height : Int) -> CollectionLayout {
  let compact = width < 640 || height < 448
  let margin = if compact { 8 } else { 20 }
  let action_height = if compact { 24 } else { 32 }
  let header_height = action_height * 4 + 12
  let status_height = if compact { 40 } else { 44 }
  let outer = @layout.layout_linear(
    axis=@layout.Vertical,
    bounds={ x: 0, y: 0, width, height, },
    tracks=[
      @layout.Fixed(header_height),
      @layout.Fill(weight=1, min=160, max=2048),
      @layout.Fixed(status_height),
    ],
    gap=8,
    padding={ top: margin, right: margin, bottom: margin, left: margin, },
    areas=@layout.Container,
  ).unwrap()
  let header = { ..outer[0], width: outer[0].width.min(480), }
  let rows = @layout.layout_linear(
    axis=@layout.Vertical,
    bounds=header,
    tracks=Array::make(4, @layout.Fixed(action_height)),
    gap=4,
  ).unwrap()
  let actions : Array[@view.Bounds] = []
  for i in 0..<3 {
    let pair = @layout.layout_linear(
      axis=@layout.Horizontal,
      bounds=rows[i],
      tracks=[
        @layout.Fill(weight=1, min=64, max=240),
        @layout.Fill(weight=1, min=64, max=240),
      ],
      gap=8,
    ).unwrap()
    actions.push(pair[0])
    actions.push(pair[1])
  }
  let search_row = @layout.layout_linear(
    axis=@layout.Horizontal,
    bounds=rows[3],
    tracks=[@layout.Fixed(64), @layout.Fill(weight=1, min=80, max=1024)],
    gap=8,
  ).unwrap()
  let body = if compact {
    @layout.layout_linear(
      axis=@layout.Vertical,
      bounds=outer[1],
      tracks=[@layout.Fixed(72), @layout.Fill(weight=1, min=80, max=1024)],
      gap=8,
    ).unwrap()
  } else {
    @layout.layout_linear(
      axis=@layout.Horizontal,
      bounds=outer[1],
      tracks=[@layout.Fixed(220), @layout.Fill(weight=1, min=80, max=1024)],
      gap=12,
    ).unwrap()
  }
  let status = @layout.layout_linear(axis=@layout.Horizontal, bounds=outer[2], tracks=[
      @layout.Fill(weight=1, min=120, max=1024),
    ]).unwrap()[0]
  {
    editor: body[1],
    list: body[0],
    actions,
    search: search_row[1],
    search_label: search_row[0],
    status,
  }
}
