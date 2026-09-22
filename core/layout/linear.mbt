///|
pub(all) enum Axis {
  Horizontal
  Vertical
} derive(Eq, Debug)

///|
pub(all) enum Track {
  Fixed(Int)
  Fill(weight~ : Int, min~ : Int, max~ : Int)
} derive(Eq, Debug)

///|
pub(all) struct Padding {
  top : Int
  right : Int
  bottom : Int
  left : Int
} derive(Eq, Debug)

///|
pub fn layout_linear(
  axis~ : Axis,
  bounds~ : @view.Bounds,
  tracks~ : Array[Track],
  gap? : Int = 0,
  padding? : Padding = { top: 0, right: 0, bottom: 0, left: 0, },
) -> Result[Array[@view.Bounds], String] {
  if bounds.x < 0 ||
    bounds.y < 0 ||
    bounds.x > 1000000 ||
    bounds.y > 1000000 ||
    bounds.width < 1 ||
    bounds.height < 1 ||
    bounds.width > 2048 ||
    bounds.height > 2048 ||
    gap < 0 ||
    gap > 2048 ||
    padding.top < 0 ||
    padding.right < 0 ||
    padding.bottom < 0 ||
    padding.left < 0 ||
    padding.top > 2048 ||
    padding.right > 2048 ||
    padding.bottom > 2048 ||
    padding.left > 2048 {
    return Err("invalid_linear_bounds")
  }
  for track in tracks {
    if !valid_track(track) {
      return Err("invalid_linear_track")
    }
  }
  let main_size = match axis {
    Horizontal => bounds.width
    Vertical => bounds.height
  }
  let cross_size = match axis {
    Horizontal => bounds.height
    Vertical => bounds.width
  }
  let main_padding = match axis {
    Horizontal => padding.left.to_int64() + padding.right.to_int64()
    Vertical => padding.top.to_int64() + padding.bottom.to_int64()
  }
  let cross_padding = match axis {
    Horizontal => padding.top.to_int64() + padding.bottom.to_int64()
    Vertical => padding.left.to_int64() + padding.right.to_int64()
  }
  let main_available = main_size.to_int64() - main_padding
  let cross_available = cross_size.to_int64() - cross_padding
  if main_available < 0L || cross_available < 0L {
    return Err("insufficient_linear_space")
  }
  if tracks.length() > 0 && cross_available < 1L {
    return Err("insufficient_linear_space")
  }
  let minimum_tracks = tracks.fold(init=0L, (sum, track) => {
    sum + track_minimum(track).to_int64()
  })
  let gaps = if tracks.length() > 1 {
    gap.to_int64() * (tracks.length() - 1).to_int64()
  } else {
    0L
  }
  if minimum_tracks + gaps > main_available {
    return Err("insufficient_linear_space")
  }
  let tree : @engine.ChicleTree[Unit] = @engine.ChicleTree()
  let leaves = tracks.map(track => tree.new_leaf(linear_leaf_style(axis, track)))
  let root = tree.new_with_children(
    linear_root_style(bounds, axis, gap, padding),
    leaves,
  )
  try {
    tree.compute_layout(root, @geometry.Size::max_content())
    let placements : Array[@view.Bounds] = []
    for index, leaf in leaves {
      let layout = tree.layout(leaf)
      let left = pixel_edge(bounds.x.to_double() + layout.location.x)
      let top = pixel_edge(bounds.y.to_double() + layout.location.y)
      let right = pixel_edge(
        bounds.x.to_double() + layout.location.x + layout.size.width,
      )
      let bottom = pixel_edge(
        bounds.y.to_double() + layout.location.y + layout.size.height,
      )
      let child = @view.Bounds::{
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      }
      if !valid_placement(bounds, child) ||
        !valid_track_size(tracks[index], axis, child) {
        return Err("linear_layout_failed")
      }
      placements.push(child)
    }
    Ok(placements)
  } catch {
    _ => Err("linear_layout_failed")
  }
}

///|
fn valid_track(track : Track) -> Bool {
  match track {
    Fixed(pixels) => pixels > 0 && pixels <= 1024
    Fill(weight~, min~, max~) =>
      weight > 0 && min > 0 && min <= max && max <= 1024
  }
}

///|
fn track_minimum(track : Track) -> Int {
  match track {
    Fixed(pixels) => pixels
    Fill(min~, ..) => min
  }
}

///|
fn linear_root_style(
  bounds : @view.Bounds,
  axis : Axis,
  gap : Int,
  padding : Padding,
) -> @style.Style {
  let gap_size = @style.DimLength(gap.to_double())
  let zero = @style.DimLength(0.0)
  let padding_rect = @geometry.Rect(
    left=@style.DimLength(padding.left.to_double()),
    right=@style.DimLength(padding.right.to_double()),
    top=@style.DimLength(padding.top.to_double()),
    bottom=@style.DimLength(padding.bottom.to_double()),
  )
  @style.Style::default()
  .with_flex_direction(
    match axis {
      Horizontal => @style.FlexRow
      Vertical => @style.FlexColumn
    },
  )
  .with_flex_wrap(@style.FlexNoWrap)
  .with_align_items(@style.ItemsStart)
  .with_size(
    @geometry.Size(
      width=@style.DimLength(bounds.width.to_double()),
      height=@style.DimLength(bounds.height.to_double()),
    ),
  )
  .with_max_size(
    @geometry.Size(
      width=@style.DimLength(2048.0),
      height=@style.DimLength(2048.0),
    ),
  )
  .with_gap(
    @geometry.Size(
      width=if axis == Horizontal { gap_size } else { zero },
      height=if axis == Vertical { gap_size } else { zero },
    ),
  )
  .with_padding(padding_rect)
  .with_overflow(
    @geometry.Point(x=@style.OverflowHidden, y=@style.OverflowHidden),
  )
}

///|
fn linear_leaf_style(axis : Axis, track : Track) -> @style.Style {
  let one = @style.DimLength(1.0)
  let leaf_max = @style.DimLength(1024.0)
  let (main_size, main_min, main_max, basis, grow) = match track {
    Fixed(pixels) => {
      let dimension = @style.DimLength(pixels.to_double())
      (dimension, dimension, dimension, @style.DimAuto, 0.0)
    }
    Fill(weight~, min~, max~) =>
      (
        @style.DimAuto,
        @style.DimLength(min.to_double()),
        @style.DimLength(max.to_double()),
        @style.DimLength(0.0),
        weight.to_double(),
      )
  }
  let size = match axis {
    Horizontal => @geometry.Size(width=main_size, height=@style.DimPercent(1.0))
    Vertical => @geometry.Size(width=@style.DimPercent(1.0), height=main_size)
  }
  let minimum = match axis {
    Horizontal => @geometry.Size(width=main_min, height=one)
    Vertical => @geometry.Size(width=one, height=main_min)
  }
  let maximum = match axis {
    Horizontal => @geometry.Size(width=main_max, height=leaf_max)
    Vertical => @geometry.Size(width=leaf_max, height=main_max)
  }
  @style.Style::default()
  .with_size(size)
  .with_min_size(minimum)
  .with_max_size(maximum)
  .with_flex_basis(basis)
  .with_flex_grow(grow)
  .with_flex_shrink(0.0)
}

///|
fn pixel_edge(value : Double) -> Int {
  (value + 0.5).to_int()
}

///|
fn valid_placement(container : @view.Bounds, child : @view.Bounds) -> Bool {
  child.width > 0 &&
  child.height > 0 &&
  child.width <= 1024 &&
  child.height <= 1024 &&
  child.x >= container.x &&
  child.y >= container.y &&
  child.x.to_int64() + child.width.to_int64() <=
  container.x.to_int64() + container.width.to_int64() &&
  child.y.to_int64() + child.height.to_int64() <=
  container.y.to_int64() + container.height.to_int64()
}

///|
fn valid_track_size(track : Track, axis : Axis, bounds : @view.Bounds) -> Bool {
  let main_size = match axis {
    Horizontal => bounds.width
    Vertical => bounds.height
  }
  match track {
    Fixed(pixels) => main_size == pixels
    Fill(min~, max~, ..) => main_size >= min && main_size <= max
  }
}
