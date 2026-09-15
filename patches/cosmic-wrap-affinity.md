# Wrapped caret affinity

The native workspace uses `Milky2018/moon_cosmic` 0.3.7 from commit
`b307f2599accac591199a7cd16ab6594067ba272`, with
`cosmic-wrap-affinity.patch`. The preparation script verifies the source archive's
SHA256 before applying the patch and compares the complete prepared source tree
on subsequent runs. Registry caches are not modified. Root-module browser builds
and standalone scripts retain their declared registry dependency.

At a soft wrap, one text offset identifies both the previous visual line's end
and the next visual line's start. Hit testing preserves that distinction through
cursor affinity, but the unpatched renderer accepts both runs and returns the
first position. Vertical movement also loses the destination side and can choose
the wrong source run on the next movement.

The patch makes rendering and vertical movement respect both sides of the
boundary. Regression tests cover one rendered caret, hit-test line retention,
successive vertical moves, and Home/End behavior on both sides. The source manifest
is also updated to the source-directory syntax accepted by the pinned compiler.

Metonic retains affinity alongside the editor revision, offset and layout width;
editing, composition and changed layout invalidate stale affinity. Drawing and
IME placement use the same retained position. This does not establish actual IME
or screen-reader acceptance, and does not add native drag selection.

The correction was developed as a local upstream candidate. It has not been
submitted or accepted upstream. Remove the local patch only after an upstream
release passes the same boundary tests and integrated native verification.
