///|
pub(all) struct Placement {
  reference : @semantics.NodeRef
  bounds : @view.Bounds
  visible : @view.Bounds?
} derive(Eq, Debug)

///|
pub struct VerticalList {
  row_height : Int
  gap : Int
  mut offset : Int
  mut extent : Int
  mut viewport : @view.Bounds
  mut placements : Array[Placement]
}

///|
pub fn VerticalList::new(
  row_height~ : Int,
  gap? : Int = 0,
) -> Result[VerticalList, String] {
  if row_height <= 0 || row_height > 1024 || gap < 0 || gap > 1024 {
    return Err("invalid_list_metrics")
  }
  Ok({
    row_height,
    gap,
    offset: 0,
    extent: 0,
    viewport: { x: 0, y: 0, width: 0, height: 0, },
    placements: [],
  })
}

///|
fn VerticalList::refresh(self : VerticalList, offset : Int) -> Unit {
  let next = offset.max(0).min((self.extent - self.viewport.height).max(0))
  let delta = self.offset - next
  self.offset = next
  self.placements = self.placements.map(placement => {
    let bounds = { ..placement.bounds, y: placement.bounds.y + delta, }
    { ..placement, bounds, visible: bounds.intersection(self.viewport), }
  })
}

///|
pub fn VerticalList::arrange(
  self : VerticalList,
  viewport : @view.Bounds,
  references : Array[@semantics.NodeRef],
) -> Result[Unit, String] {
  if viewport.x < 0 ||
    viewport.y < 0 ||
    viewport.width < 1 ||
    viewport.height < 1 ||
    viewport.x > 1000000 ||
    viewport.y > 1000000 ||
    viewport.width > 1024 ||
    viewport.height > 1024 ||
    references.length() > 100000 {
    return Err("invalid_list_bounds")
  }
  let seen : Map[(Int, Int, Int, Int), Bool] = Map([])
  for reference in references {
    let key = (
      reference.session,
      reference.window,
      reference.id,
      reference.generation,
    )
    if seen.contains(key) {
      return Err("duplicate_list_reference")
    }
    seen[key] = true
  }
  let tree : @engine.ChicleTree[Unit] = @engine.ChicleTree()
  let row_style = @style.Style::default()
    .with_size(
      @geometry.Size(
        width=@style.DimPercent(1.0),
        height=@style.DimLength(self.row_height.to_double()),
      ),
    )
    .with_flex_shrink(0.0)
  let nodes = references.map(_ => tree.new_leaf(row_style))
  let root = tree.new_with_children(
    @style.Style::default()
    .with_flex_direction(@style.FlexColumn)
    .with_gap(
      @geometry.Size(
        width=@style.DimLength(0.0),
        height=@style.DimLength(self.gap.to_double()),
      ),
    )
    .with_size(
      @geometry.Size(
        width=@style.DimLength(viewport.width.to_double()),
        height=@style.DimLength(viewport.height.to_double()),
      ),
    )
    .with_overflow(
      @geometry.Point(x=@style.OverflowHidden, y=@style.OverflowScroll),
    ),
    nodes,
  )
  try {
    tree.compute_layout(root, @geometry.Size::max_content())
    let extent = tree.layout(root).content_size.height.to_int()
    let offset = self.offset.min((extent - viewport.height).max(0))
    let placements : Array[Placement] = []
    for index, node in nodes {
      let result = tree.layout(node)
      let bounds : @view.Bounds = {
        x: viewport.x + result.location.x.to_int(),
        y: viewport.y + result.location.y.to_int() - offset,
        width: result.size.width.to_int(),
        height: result.size.height.to_int(),
      }
      placements.push({
        reference: references[index],
        bounds,
        visible: bounds.intersection(viewport),
      })
    }
    self.viewport = viewport
    self.extent = extent
    self.offset = offset
    self.placements = placements
    Ok(())
  } catch {
    _ => Err("list_layout_failed")
  }
}

///|
pub fn VerticalList::items(self : VerticalList) -> Array[Placement] {
  self.placements.copy()
}

///|
pub fn VerticalList::scroll_at(
  self : VerticalList,
  x : Int,
  y : Int,
  pixels : Int,
) -> Bool {
  self.viewport.contains(x, y) && self.scroll(pixels)
}

///|
pub fn VerticalList::scroll(self : VerticalList, pixels : Int) -> Bool {
  let before = self.offset
  let next = (before.to_int64() + pixels.to_int64())
    .max(0L)
    .min((self.extent - self.viewport.height).max(0).to_int64())
    .to_int()
  self.refresh(next)
  before != self.offset
}

///|
pub fn VerticalList::reveal(
  self : VerticalList,
  reference : @semantics.NodeRef,
) -> Bool {
  guard self.placements.iter().find_first(p => p.reference == reference)
    is Some(p) else {
    return false
  }
  let delta = if p.bounds.y < self.viewport.y {
    p.bounds.y - self.viewport.y
  } else if p.bounds.y + p.bounds.height >
    self.viewport.y + self.viewport.height {
    p.bounds.y + p.bounds.height - self.viewport.y - self.viewport.height
  } else {
    0
  }
  self.scroll(delta)
}

///|
pub fn VerticalList::hit(
  self : VerticalList,
  x : Int,
  y : Int,
) -> @semantics.NodeRef? {
  self.placements
  .iter()
  .find_first(p => p.visible is Some(bounds) && bounds.contains(x, y))
  .map(p => p.reference)
}
