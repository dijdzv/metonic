///|
fn text(app : @app.Application, index : Int) -> String {
  ignore(app.synchronize_components(None))
  let y = if index == 8 { 400 } else { 112 + (index - 4) * 48 }
  (app.view)()
  .iter()
  .find_first(control => control.element.bounds.y == y)
  .unwrap().element.text
}

///|
fn button(app : @app.Application, name : String) -> @semantics.NodeRef {
  (app.view)()
  .iter()
  .find_first(control => control.element.text == name)
  .unwrap().element.reference.unwrap()
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
  let diagnostics = @async_state.TraceRegistry::new(128)
  let app = @board.create(
    milliseconds => @clock.Clock::sleep(clock, milliseconds),
    diagnostics=Some(diagnostics),
  )
  let amber_button = button(app, "Amber lamp")
  let blue = button(app, "Blue stool")
  let toggle_detail = button(app, "Toggle detail")
  let yen = button(app, "JPY")
  let dollar = button(app, "USD")
  let heading = (app.view)().filter(control => control.kind == @app.Text)[0].element.reference.unwrap()
  assert_eq(
    @semantics.node(app.editor, heading).unwrap().role,
    @semantics.Label,
  )
  let completed = Ref(false)
  @window_host.run(
    @host.from_application(app),
    hidden=true,
    controller=Some(handle => {
      @async.with_timeout(15000, async fn() {
        wait_text(app, 7, "Shipping: 112 for 1")
        let first_trace = (handle.inspect)().diagnostics.unwrap()
        assert_eq(diagnostics.owners().length(), 3)
        assert_eq(diagnostics.sources().length(), 4)
        assert_eq(diagnostics.derived()[0].phase, "ready")
        assert_true(first_trace.stringify().contains("\"sources\""))
        let increase = button(app, "Quantity +")
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
        let joined_before = diagnostics
          .events()
          .filter(event => event.kind == @async_state.CleanupJoined)
          .length()
        assert_eq(
          (handle.operate)(
            amber_button,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        @async.with_timeout(5000, () => {
          while diagnostics
                .events()
                .filter(event => event.kind == @async_state.CleanupJoined)
                .length() <=
                joined_before {
            @async.sleep(20)
          }
        })
        assert_true(
          diagnostics
          .events()
          .any(event => event.kind == @async_state.CancellationRequested),
        )
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
        assert_eq(text(app, 4), "Item: blue · Quantity: 1 · Currency: JPY")
        assert_eq(
          @semantics.node(app.editor, heading).unwrap().name,
          "Item: blue · Quantity: 1 · Currency: JPY",
        )
        assert_eq(text(app, 7), "Shipping: waiting for item")
        wait_text(app, 5, "Detail: Blue stool")
        assert_eq(text(app, 6), "Stock: loading")
        let partial = (handle.capture)(_ => ())
        assert_true(partial.pixels != amber.pixels)
        wait_text(app, 7, "Shipping: 107 for 1")
        assert_true(
          diagnostics
          .events()
          .any(event => event.kind == @async_state.OwnerDisposed),
        )
        assert_true(
          diagnostics
          .events()
          .any(event => event.kind == @async_state.SourceDisposed),
        )
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
        let blue_increase = button(app, "Quantity +")
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
        wait_text(app, 7, "Shipping: loading")
        assert_eq(
          (handle.operate)(
            toggle_detail,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        assert_eq(text(app, 7), "Shipping: detail hidden")
        assert_true(
          diagnostics
          .events()
          .any(event => event.kind == @async_state.CancellationRequested),
        )
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
        let recreated_increase = button(app, "Quantity +")
        assert_true(recreated_increase != blue_increase)
        wait_text(app, 7, "Shipping: 321 for 3")
        assert_eq(
          (handle.operate)(
            dollar,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        assert_eq(text(app, 7), "Shipping: loading")
        assert_eq(
          (handle.operate)(
            yen,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        assert_eq(text(app, 7), "Shipping: 321 for 3")
        assert_eq(
          (handle.operate)(
            dollar,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        wait_text(app, 7, "Shipping: 642 USD for 3")
        assert_eq(
          (handle.operate)(
            recreated_increase,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        wait_text(app, 7, "Shipping: failed for blue x4")
        assert_true(
          diagnostics
          .events()
          .any(event => event.kind == @async_state.ExpectedFailure),
        )
        let retry = (app.view)()
        .iter()
        .find_first(control => control.element.text == "Retry quote")
        .unwrap().element.reference.unwrap()
        assert_eq(
          (handle.operate)(
            retry,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        wait_text(app, 7, "Shipping: 856 USD for 4")
        let note = app.default_input.unwrap()
        let save = (app.view)()
        .iter()
        .find_first(control => control.element.text == "Save note")
        .unwrap().element.reference.unwrap()
        assert_eq(
          (handle.operate)(
            note,
            @window_host.InsertText("first draft"),
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        assert_eq(text(app, 8), "Note: unsaved revision 1")
        assert_eq(
          (handle.operate)(
            save,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        wait_text(app, 8, "Note: saving revision 1")
        assert_eq(
          (handle.operate)(
            note,
            @window_host.InsertText(" newer draft"),
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        assert_eq(
          (handle.operate)(
            save,
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
        wait_text(app, 8, "Note: saved revision 1; saving revision 2")
        wait_text(app, 8, "Note: saved revision 2")
        assert_false(
          (handle.inspect)().diagnostics
          .unwrap()
          .stringify()
          .contains("newer draft"),
        )
        assert_eq((handle.inspect)().text, "first draft newer draft")
        assert_eq(
          (handle.operate)(
            note,
            @window_host.InsertText(" close draft"),
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        assert_false((app.can_close)())
        (handle.apply)(@window_host.Close)
        assert_false((handle.inspect)().closed)
        completed.val = true
      })
    }),
    diagnostics=Some(diagnostics),
  )
  assert_true(completed.val)
  println("QUOTE_BOARD_NATIVE_OK")
}
