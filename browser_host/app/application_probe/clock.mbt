///|
let clock_result : Ref[Int] = Ref(0)

///|
#export_name("clock_status")
pub fn clock_status() -> Int {
  clock_result.val
}

///|
#export_name("clock_start")
pub fn clock_start() -> Unit {
  clock_result.val = 0
  @async.run_async_main(() => {
    let clock = @production_clock.SystemClock::new()
    let canceled_completed = Ref(false)
    let valid = @async.with_task_group(group => {
      let canceled = group.spawn(() => {
        @async.with_task_group(owner => {
          owner.spawn_bg(() => {
            ignore(@clock.after(clock, 60000, 0))
            canceled_completed.val = true
          })
          @async.pause()
          owner.return_immediately(())
        })
      })
      let kept = group.spawn(() => @clock.after(clock, 20, 2))
      canceled.wait()
      let result = kept.wait()
      let started = @clock.Clock::now(clock)
      let repeated = @clock.after(clock, 20, 3)
      result == 2 &&
      repeated == 3 &&
      @clock.Clock::now(clock) - started >= 10L &&
      !canceled_completed.val
    }) catch {
      _ => false
    }
    clock_result.val = if valid { 1 } else { -1 }
  })
}
