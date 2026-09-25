///|
let active_trace : Ref[@async_state.TraceRegistry?] = Ref(None)

///|
#export_name("create")
pub fn create() -> @host.Instance {
  let clock = @production_clock.SystemClock::new()
  let diagnostics = @async_state.TraceRegistry::new(128)
  active_trace.val = Some(diagnostics)
  @host.create(
    @board.create(
      milliseconds => @clock.Clock::sleep(clock, milliseconds),
      diagnostics=Some(diagnostics),
    ),
    [],
    root_id=Some("controls"),
    canvas_id="canvas",
    event_name="quote-board-refresh",
    font_url="./NotoSansJP.ttf",
    font_sha256="c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f",
    diagnostics=Some(diagnostics),
  )
}

///|
#export_name("diagnostics_json")
pub fn diagnostics_json() -> String {
  active_trace.val
  .map(registry => registry.snapshot_json().stringify())
  .unwrap_or("null")
}
