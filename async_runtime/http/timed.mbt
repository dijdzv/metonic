///|
pub(all) struct TimedHttp[H, C] {
  transport : H
  clock : C
  milliseconds : Int
}

///|
pub impl[H : @capability.Http, C : @clock.Clock] @capability.Http for TimedHttp[
  H,
  C,
] with fn post(self, request) {
  @clock.validate_delay(self.milliseconds)
  if request.response_limit < 0 {
    return Err(@capability.InvalidRequest)
  }
  if self.milliseconds == 0 {
    return Err(@capability.Timeout)
  }
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      self.clock.sleep(self.milliseconds)
      group.return_immediately(Err(@capability.Timeout))
    })
    let result = self.transport.post(request)
    group.return_immediately(result)
    result
  })
}
