///|
priv struct PendingHttp {
  id : Int
  transport : @http_transport.Transport
  mut task : @async.Task[Unit]?
  mut live : Bool
}

///|
let pending_http : Ref[PendingHttp?] = Ref(None)

///|
#export_name("http_cancel")
pub fn http_cancel() -> Unit {
  if pending_http.val is Some(request) {
    pending_http.val = None
    request.live = false
    request.transport.cleanup()
    if request.task is Some(task) {
      @async.run_async_main(() => task.cancel())
    }
  }
}

///|
#export_name("http_start")
pub fn http_start() -> Int {
  if inputs_composing() != 0 {
    return 0
  }
  guard @input_binding.input("rpc-user") is Some(input) else { return 0 }
  let user_id = @input_binding.SingleLine(input).value()
  guard @app.rpc_prepare(user_id) is Some(_) else { return 0 }
  http_cancel()
  let id = @app.task_begin()
  if id < 0 {
    return 0
  }
  let request = PendingHttp::{
    id,
    transport: @http_transport.create(),
    task: None,
    live: true,
  }
  pending_http.val = Some(request)
  @async.run_async_main(async fn() {
    @async.with_task_group(group => {
      let task = group.spawn(() => {
        if !request.live {
          return
        }
        let clock = @clock_driver.create()
        let result = @user_load.load(
          @timed.TimedHttp::{
            transport: request.transport,
            clock,
            milliseconds: 3000,
          },
          user_id,
        )
        if !request.live {
          return
        }
        request.live = false
        if pending_http.val is Some(current) && current.id == request.id {
          pending_http.val = None
        }
        if @app.rpc_apply(id, result.map(user => user.name)) == 1 {
          http_notify()
        }
      })
      request.task = Some(task)
      task.wait() catch {
        @async.TaskCancelled => ()
        _ =>
          if request.live {
            request.live = false
            if pending_http.val is Some(current) && current.id == request.id {
              pending_http.val = None
            }
            if @app.rpc_transport_error(id, 0) == 1 {
              http_notify()
            }
          }
      }
    })
  })
  1
}
