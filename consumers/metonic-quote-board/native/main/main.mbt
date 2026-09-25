///|
async fn main {
  let clock = @production_clock.SystemClock::new()
  @window_host.run(
    @host.from_application(
      @board.create(milliseconds => @clock.Clock::sleep(clock, milliseconds)),
    ),
  )
}
