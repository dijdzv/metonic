///|
pub async fn verify() -> Unit {
  @async.with_timeout(5000, () => {
    let clock = @production_clock.SystemClock::new()
    let driver = @driver.driver()
    let canceled = @task.Operation::new()
    let kept = @task.Operation::new()
    let ready = @cond_var.Cond()
    let finished = @cond_var.Cond()
    let result = Ref(0)
    assert_true(
      driver.submit(
        @task.replace(
          () => (),
          () => {
            Some(
              @task.work(
                () => {
                  ready.signal()
                  @clock.after(clock, 60000, -1)
                },
                value => {
                  result.val = value
                  @task.Changed
                },
              ),
            )
          },
          operation=canceled,
        ),
      ),
    )
    @async.with_task_group(group => {
      let running = group.spawn(() => {
        driver.run(completion => ignore(completion.apply()))
      })
      ready.wait()
      assert_true(
        driver.submit(
          @task.replace(
            () => (),
            () => {
              Some(
                @task.work(
                  () => {
                    ignore(@clock.after(clock, 10, 1))
                    @clock.after(clock, 10, 2)
                  },
                  value => {
                    result.val = value
                    finished.signal()
                    @task.Changed
                  },
                ),
              )
            },
            operation=kept,
          ),
        ),
      )
      assert_true(driver.submit(@task.cancel(() => (), operation=canceled)))
      finished.wait()
      driver.close()
      running.wait()
    })
    assert_eq(result.val, 2)
  })
}
