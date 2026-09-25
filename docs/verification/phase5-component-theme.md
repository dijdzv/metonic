# Phase 5 component theme and gallery verification

The shared theme is owned by one `UiRoot`. Browser JS, browser WasmGC and
Windows native receive its typography, spacing and colors through the same
`Application` view and raster path. The default tokens preserve the earlier
palette. `set_theme` marks an application event for synchronization; it does
not mutate a frame while it is rendered.

The fixed Windows rendering test uses the packaged Noto Sans JP font and three
distinct labels. Its first frame builds three text layouts and paints three
layers. A second frame with the same text and widths paints three layers,
records three layout-cache hits and builds no layouts. A focus change, a
foreground/background change and a disabled-state change each paint one layer
without another layout build. Changing typography from 24/32 to 26/34 builds
one new layout. The native input-layout test verifies that the changed
typography invalidates its geometry match. The cache is bounded to 64 layouts
per raster engine. These are deterministic work counts, not elapsed-time or
whole-application throughput claims.

The headless component gallery exercises Checkbox, Label, Button, single- and
multiline input, Status and Retry, Stack, ScrollView and selectable List on
both browser targets. It checks disabled and error semantics, focus and
keyboard actions, keyed removal/recreation, row reorder, scrolling, async
completion and theme repaint. The Windows UIA probe checks the corresponding
roles and states, disabled button, async Status update and theme action in an
owned window. The existing Notes and quote-board flows remain independent
regression consumers.

The browser host currently repaints its frame when the theme changes. Native
presentation also repaints prepared layers when the theme changes. Layout
reuse removes repeated shaping for unchanged inputs but does not claim dirty
rectangle repainting or a reduction in GPU submissions. The browser gallery
asserts a visible pixel difference; the shared renderer's deterministic counts
establish why that repaint did not need new text shaping. Physical IME behavior
is outside this synthetic gallery check.
