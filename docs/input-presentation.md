# Input presentation state

Semantic editing state belongs to `core/semantics`. Presentation state is keyed
by its complete `NodeRef` (session, window, node ID and generation), rather than
by an application's control names or positions in a snapshot.

`core/input_navigation` records caret affinity and the preferred horizontal
position for vertical navigation. A lookup requires the same live input,
semantic revision, caret offset and layout width. Composition suppresses the
stored affinity. The current policy conservatively invalidates navigation on
any semantic revision; it does not infer whether an unrelated edit preserves
the input's geometry. Hosts reset navigation when ordinary editing or focus
actions invalidate a vertical-navigation sequence.

`native_host/input_layout` registers a font-backed raster engine for each input,
with an explicit single-line or multiline mode. Registration rejects duplicate,
stale, foreign and non-input references. Separate engines retain independent
hit-test and caret geometry. Single-line preparation measures unscrolled text,
clamps horizontal scrolling after text shrinks, and optionally follows the
active caret. Multiline rendering retains the raster engine's vertical scroll;
the host synchronizes it after rendering. The rasterizer's existing size limits
still apply.

Removing an input or closing its semantic tree makes registry lookups fail.
Reusing a node ID with a new generation requires fresh registration. `remove`
releases a registration and `clear` releases all registrations at host shutdown.
Previously returned raster engines are ordinary borrowed-by-convention handles,
not revocable capabilities; callers must resolve the current reference before
using geometry after a semantic change.

The P0 host supplies its editor and query references, modes and view geometry.
Its control routing and render invalidation remain application-specific. These
packages remove fixed input storage, but do not yet constitute a general native
application host or provide multiple simultaneous full AccessKit text layouts.

Focused tests cover input isolation, revision/layout invalidation, composition
affinity, stale generations, disposal, single-line scrolling and multiline
geometry. Native layout tests require the prepared font through
`METONIC_RENDER_TEST_FONT`; the normal native workspace verification prepares it.
These tests do not establish physical IME behavior.
