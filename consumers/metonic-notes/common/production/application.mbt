///|
pub fn create_collection(
  store : @persistence.Store,
  dispose : async () -> Unit,
) -> @application.Application {
  let clock = @production_clock.SystemClock::new()
  @model.create_collection(store, dispose, milliseconds => {
    @clock.Clock::sleep(clock, milliseconds)
  })
}
