///|
async fn verify_operations() -> Unit {
  let model = @operations.create(() => @async.CondVar::Cond().wait())
  let app = model.application()
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
