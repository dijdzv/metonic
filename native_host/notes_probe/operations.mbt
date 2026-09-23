///|
async fn verify_operations() -> Unit {
  let model = @operations.create(() => @async.CondVar::Cond().wait())
  let base = model.application()
  let control : Ref[@task.TaskControl?] = Ref(None)
  let app = {
    ..base,
    connect_tasks: value => {
      if control.val is Some(_) {
        abort("task control connected twice")
      }
      control.val = Some(value)
    },
    initialize: () => {
      if control.val is None {
        abort("task control was not connected before initialize")
      }
      (base.initialize)()
    },
  }
  let completed = Ref(false)
  @window_host.run(
    @host_application.from_application(app),
    hidden=true,
    controller=Some(handle => {
      @async.with_timeout(5000, () => {
        let activate = (index : Int) => {
          let reference = (app.view)()[index].element.reference.unwrap()
          assert_eq(
            (handle.operate)(
              reference,
              ActivateControl,
              @semantics.revision(app.editor),
            ),
            "",
          )
        }
        let wait_state = (index : Int, value : Int) => {
          while model.state(index) != value {
            @async.sleep(1)
          }
        }
        activate(0)
        wait_state(0, 1)
        activate(1)
        wait_state(1, 1)
        assert_eq(model.state(0), 1)
        assert_eq(model.state(3), 0)
        activate(3)
        wait_state(2, 1)
        assert_eq(model.state(0), 1)
        activate(2)
        wait_state(0, 3)
        wait_state(3, 1)
        activate(1)
        wait_state(1, 2)
        activate(0)
        wait_state(0, 1)
        control.val.unwrap().cancel(model.slow_operation())
        wait_state(3, 2)
        assert_eq(model.state(0), 1)
        completed.val = true
        (handle.apply)(Close)
      })
    }),
  )
  assert_true(completed.val)
  assert_eq(model.state(3), 2)
  assert_eq(model.state(4), 1)
  println("INDEPENDENT_OPERATIONS_NATIVE_OK")
}
