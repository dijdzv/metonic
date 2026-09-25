///|
extern "C" fn current_process() -> UInt64 = "GetCurrentProcess"

///|
#borrow(counters)
extern "C" fn process_memory(
  process : UInt64,
  counters : FixedArray[UInt64],
  size : UInt,
) -> Int = "K32GetProcessMemoryInfo"

///|
#borrow(count)
extern "C" fn process_handles(process : UInt64, count : FixedArray[Int]) -> Int = "GetProcessHandleCount"

///|
fn text(app : @app.Application, index : Int) -> String {
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
      @async.sleep(10)
    }
  })
}

///|
async fn main {
  let args = @env.args()
  assert_eq(args.length(), 2, msg="usage: measure.exe <sample-index>")
  let sample = args[1]
  assert_true(sample == "0" || sample == "1" || sample == "2" || sample == "3")
  let started = @async.now()
  let clock = @production_clock.SystemClock::new()
  let app = @board.create(milliseconds => {
    @clock.Clock::sleep(clock, milliseconds)
  })
  let blue = button(app, "Blue stool")
  let toggle = button(app, "Toggle detail")
  let dollar = button(app, "USD")
  let note = app.default_input.unwrap()
  let save = (app.view)()
  .iter()
  .find_first(control => control.element.text == "Save note")
  .unwrap().element.reference.unwrap()
  let metrics : Array[(String, Int)] = []
  let completed = Ref(false)
  @window_host.run(
    @host.from_application(app),
    hidden=true,
    controller=Some(handle => {
      @async.with_timeout(20000, async fn() {
        let elapsed = () => (@async.now() - started).to_int()
        wait_text(app, 7, "Shipping: 112 for 1")
        metrics.push(("initial_quote_ready", elapsed()))

        let item_started = @async.now()
        assert_eq(
          (handle.operate)(
            blue,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        wait_text(app, 7, "Shipping: waiting for item")
        metrics.push(("item_pending", (@async.now() - item_started).to_int()))
        wait_text(app, 7, "Shipping: 107 for 1")
        metrics.push(("item_ready", (@async.now() - item_started).to_int()))

        let currency_started = @async.now()
        assert_eq(
          (handle.operate)(
            dollar,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        wait_text(app, 7, "Shipping: loading")
        metrics.push(
          ("currency_pending", (@async.now() - currency_started).to_int()),
        )
        wait_text(app, 7, "Shipping: 214 USD for 1")
        metrics.push(
          ("currency_ready", (@async.now() - currency_started).to_int()),
        )

        let hide_started = @async.now()
        assert_eq(
          (handle.operate)(
            toggle,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        wait_text(app, 7, "Shipping: detail hidden")
        metrics.push(("detail_hidden", (@async.now() - hide_started).to_int()))
        let show_started = @async.now()
        assert_eq(
          (handle.operate)(
            toggle,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        wait_text(app, 7, "Shipping: 214 USD for 1")
        metrics.push(
          ("detail_recreated", (@async.now() - show_started).to_int()),
        )

        let input_started = @async.now()
        assert_eq(
          (handle.operate)(
            note,
            @window_host.InsertText("measurement draft"),
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        wait_text(app, 8, "Note: unsaved revision 1")
        metrics.push(("input_visible", (@async.now() - input_started).to_int()))
        let save_started = @async.now()
        assert_eq(
          (handle.operate)(
            save,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        wait_text(app, 8, "Note: saved revision 1")
        metrics.push(
          ("save_acknowledged", (@async.now() - save_started).to_int()),
        )

        let counters = FixedArray::make(10, 0UL)
        counters[0] = 80UL
        let count = FixedArray::make(1, 0)
        let process = current_process()
        assert_true(process_memory(process, counters, 80U) != 0)
        assert_true(process_handles(process, count) != 0)
        println(
          "QUOTE_BOARD_NATIVE_RESOURCE sample=" +
          sample +
          " working_set_bytes=" +
          counters[2].to_string() +
          " private_bytes=" +
          counters[9].to_string() +
          " handles=" +
          count[0].to_string(),
        )
        assert_true((app.can_close)())
        completed.val = true
        (handle.apply)(@window_host.Close)
      })
    }),
  )
  assert_true(completed.val)
  for (name, duration) in metrics {
    println(
      "QUOTE_BOARD_NATIVE_MEASURE sample=" +
      sample +
      " metric=" +
      name +
      " ms=" +
      duration.to_string(),
    )
  }
  println("QUOTE_BOARD_NATIVE_MEASUREMENT_SAMPLE_OK sample=" + sample)
}
