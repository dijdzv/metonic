# Application-defined rendering items

`core/view` provides `Bounds` and `Element`. An application supplies each
element's rectangle, text, optional semantic reference and focus state. It owns
layout and action policy. These types do not refer to P0 controls or HTTP.

`core/view_renderer.item` combines an element with its drawing surface and input
presentation: selection ranges, caret, caret affinity, horizontal or vertical
scroll, and the caret to keep visible. The current surfaces are plain `Text` and
bordered `Control`. Controls preserve the initial renderer's fixed border and
text padding; this is not yet a theme or component system.

`core/view_renderer.render(engine, items, retain_layout=index)` returns layers
in the same order as `items`. Their pixels use local coordinates; their bounds
specify placement for the host compositor. Semantic references are metadata and
do not trigger actions or focus changes during rendering.

The optional retained-item index identifies the layout that must remain in the
provided text engine for subsequent hit testing, caret geometry and IME. That
item is rasterized last without moving its composited layer. Without an explicit
index, the last item retains its layout. An empty item list leaves the engine
unchanged. Each engine retains one layout; callers needing independent layouts
for several inputs must use separate engines or explicitly render the required
layout before querying it. A bordered control's layout is relative to its text
area, including the host's responsibility to account for padding.

The result is `Err("invalid_retained_item")` for an out-of-range retained index,
or `Err("invalid_item_bounds")` for rectangles outside the current rasterizer's
limits: width 1–1024 and height 1–96. Validation happens before any item is
rasterized. Larger editor content uses scrolling inside its viewport; larger
viewports remain a separate rasterizer extension.

P0's adapter assembles its editor, buttons, labels and query field into these
items. The shared renderer does not know their names, roles in the sample, or
which HTTP operation a button starts. Its existing host invalidation logic is
preserved. The independent native rendering test uses a different arrangement,
compares input pixels and hit geometry with direct rasterization, and changes
layout retention without changing layer order. It runs in the native workspace
verification alongside the existing browser and native integration gates.
