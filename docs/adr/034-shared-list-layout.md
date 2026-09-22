# ADR 034: Scoped Chicle adoption for shared vertical lists

## Status

Accepted for fixed-height vertical lists. A general-purpose layout engine has
not been adopted.

## Context

The initial library evaluation on 2026-09-06 recorded no selected layout engine
and compared a Chicle 0.6.0 checkout. Since then, native and browser application
views need the same bounded behavior for fixed-height rows: placement, clipping,
pixel scrolling, visible hit testing and focus reveal. The root module now pins
`Milky2018/chicle@0.6.1`, and `core/layout` implements that shared behavior.

The application contract already carries `Control.clip` and an optional
`Application.viewport`. Hosts must preserve those semantics while using their
own rendering, DOM and input mechanisms. This does not require a general CSS or
DOM layout engine.

## Decision

Use Chicle 0.6.1 behind `core/layout.VerticalList` and `layout_linear`. The list
facade
accepts unique semantic references and arranges them as a single column of
equal-height rows. It returns each reference's bounds and visible intersection,
retains a clamped pixel scroll offset, resolves hits only in visible bounds, and
can reveal a referenced row. Applications continue to define control content,
view state, and how placements map to controls. Do not expose Chicle tree/style
types as the application contract.

`layout_linear` exposes fixed and weighted fill tracks with gap and padding for
one horizontal or vertical arrangement. A caller may arrange an editor beside
a list, or nest another call using a returned area. Fixed tracks never shrink;
fill tracks carry explicit minimum and maximum sizes. The application chooses
the composition for each window size. The primitive reports insufficient space
instead of assigning overlapping bounds and owns no scrolling state.

This is not a general layout system: row height and gap are fixed pixels; rows
are not measured from their content; arbitrary nesting, general measurement,
responsive rules and list virtualization are outside this API. `arrange` creates
layout nodes for every supplied reference and returns a placement for every row,
including offscreen rows.

`Control.clip` is the shared clipping input. The native renderer crops pixels to
the intersection, uses the clipped bounds for hit testing, and publishes those
bounds to accessibility. The browser managed host applies the intersection as
CSS `clip-path`. `Application.viewport.scroll` receives host pointer coordinates
and a pixel delta; native sends unhandled wheel events to it, while the browser
converts wheel units to pixels and leaves text-input scrolling to the input
controls. Each host calls `reveal` on a semantic focus change and rebuilds its
view when the callback changes the placements. This app viewport is separate
from an individual text input's internal scroll position.

## Limits and costs

The current API enforces these limits:

- Row height: 1–1024 pixels; gap: 0–1024 pixels.
- Viewport width and height: 1–1024 pixels; origin coordinates: 0–1,000,000.
- At most 100,000 unique semantic references per arrangement.
- Raster layer dimensions: 1–1024 pixels per axis on native and browser.
- Linear layout root: 1–2048 pixels per axis; returned drawable areas: at most
  1024 pixels per axis.
- Native surface: at most 64 raster layers in an installed layer set.

The list API does not enforce the native surface's layer count, and a dense
viewport may produce more than 64 visible rows. Clipping removes fully hidden
layers before GPU installation, but all supplied references are laid out and
offscreen controls may still incur CPU raster work. Filtering controls out of a
view also affects focus order and browser accessibility, so applications need
an explicit navigation policy before treating that as virtualization. The
native surface additionally limits raster origins to 0–2048 pixels, even though
`VerticalList.arrange` accepts origin coordinates up to 1,000,000.

The 64-layer ceiling is a native surface limit, not a target count and not a
browser guarantee. A submitted native layer set creates an RGBA8 texture, view,
shader module, render pipeline and bind group for every layer, uploads the full
pixel buffer for each, and releases the previous set. The browser also uploads
each submitted layer and replaces its previous set. Raster area and layer count
therefore drive CPU pixel generation, transfer volume and GPU resource churn;
this record contains no performance benchmark.

The independent Notes application has not migrated to `VerticalList`:
`examples/notes/application/application.mbt` still supplies explicit bounds and
sets `viewport: None`. Adopting this primitive does not mean that application
migration is complete.

## Verification scope

The `core/layout/list_test.mbt` cases cover partial-row intersections,
visible hit testing, scroll clamping, focus reveal, reorder/resize/removal,
duplicate references and rejection of invalid bounds while preserving the last
valid layout. `native_host/notes_probe/viewport.mbt` contains an owned-window
probe for clipped and hidden rows, wheel scrolling, focus reveal, resize,
clipped accessibility bounds, and rendering of 20 simultaneously visible rows.
`core/layout/linear_test.mbt` covers fixed/fill placement and rejection of
insufficient space on JS, WasmGC and native. Consumer integration remains open.

The browser implementation is connected through
`browser_host/app/application_host/viewport.mbt`, `controls.mbt`, `session.mbt`
and `browser_host/app/dom_view/placement.mbt`; the application probe wires the
same list/clip callbacks. The browser headless gate passed on JS and WasmGC with
eight-row wheel scrolling, focus reveal, retained DOM identities, and stop
cleanup. This does not establish physical browser IME behavior, cross-browser
parity, virtualization, or performance at the 100,000-reference limit. The
earlier 0.6.0 upstream checks in the
[library reuse record](../verification/library-reuse.md) remain historical
comparison results and are not treated as 0.6.1 verification.

See the [application entry](../application-entry.md) for the current API
description and host boundaries.
