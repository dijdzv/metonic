///|
fn text(app : @app.Application, index : Int) -> String {
  (app.view)()[index + 1].element.text
}

///|
async fn wait_text(
  app : @app.Application,
  index : Int,
  expected : String,
) -> Unit {
  @async.with_timeout(10000, () => {
    while text(app, index) != expected {
      @async.sleep(20)
    }
  })
}

///|
async fn main {
  let clock = @production_clock.SystemClock::new()
  let app = @board.create(milliseconds => {
    @clock.Clock::sleep(clock, milliseconds)
  })
  let amber_button = (app.view)()[0].element.reference.unwrap()
  let blue = (app.view)()[1].element.reference.unwrap()
  let toggle_detail = (app.view)()[3].element.reference.unwrap()
  let completed = Ref(false)
  @window_host.run(
    @host.from_application(app),
    hidden=true,
    controller=Some(handle => {
      @async.with_timeout(15000, async fn() {
        wait_text(app, 7, "Shipping: 112 for 1")
        let increase = (app.view)()[4].element.reference.unwrap()
        let amber = (handle.capture)(_ => ())
        assert_eq(amber.pixels.length(), amber.width * amber.height * 4)
        assert_eq(
          (handle.operate)(
            amber_button,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        assert_eq(text(app, 5), "Detail: loading")
        wait_text(app, 6, "Stock: 12")
        assert_eq(text(app, 5), "Detail: loading")
        wait_text(app, 7, "Shipping: 112 for 1")
        assert_eq(
          (handle.operate)(
            blue,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        assert_eq(text(app, 4), "Item: blue · Quantity: 1")
        assert_eq(text(app, 7), "Shipping: waiting for item")
        wait_text(app, 5, "Detail: Blue stool")
        assert_eq(text(app, 6), "Stock: loading")
        let partial = (handle.capture)(_ => ())
        assert_true(partial.pixels != amber.pixels)
        wait_text(app, 7, "Shipping: 107 for 1")
        let ready = (handle.capture)(_ => ())
        assert_true(ready.pixels != partial.pixels)
        assert_eq(
          (handle.operate)(
            increase,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "stale_target",
        )
        let blue_increase = (app.view)()[4].element.reference.unwrap()
        assert_true(blue_increase != increase)
        assert_eq(
          (handle.operate)(
            blue_increase,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        wait_text(app, 7, "Shipping: 214 for 2")
        assert_eq(
          (handle.operate)(
            blue_increase,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        assert_eq(
          (handle.operate)(
            toggle_detail,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        assert_eq((app.view)()[7].element.text, "Shipping: detail hidden")
        assert_eq(
          (handle.operate)(
            blue_increase,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "stale_target",
        )
        assert_eq(
          (handle.operate)(
            toggle_detail,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        let recreated_increase = (app.view)()[4].element.reference.unwrap()
        assert_true(recreated_increase != blue_increase)
        wait_text(app, 7, "Shipping: 321 for 3")
        completed.val = true
        (handle.apply)(@window_host.Close)
      })
    }),
  )
  assert_true(completed.val)
  println("QUOTE_BOARD_NATIVE_OK")
}
