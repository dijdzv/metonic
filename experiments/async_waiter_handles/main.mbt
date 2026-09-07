///|
extern "C" fn event_bus_create() -> UInt64 = "moonbitlang_async_event_bus_create"

///|
extern "C" fn event_bus_destroy(bus : UInt64) -> Unit = "moonbitlang_async_event_bus_destroy"

///|
extern "C" fn spawn_waiter(
  bus : UInt64,
  wakeup_callback~ : FuncRef[() -> Unit],
) -> UInt64 = "moonbitlang_async_spawn_event_bus_waiter"

///|
extern "C" fn terminate_waiter(waiter : UInt64) -> Unit = "moonbitlang_async_terminate_event_bus_waiter"

///|
extern "C" fn process_handle_count() -> Int = "metonic_process_handle_count"

///|
extern "C" fn noop_callback() -> FuncRef[() -> Unit] = "metonic_noop_callback"

///|
fn require(value : Bool, message : String) -> Unit {
  if !value {
    abort(message)
  }
}

///|
fn run_cycle() -> Unit {
  let bus = event_bus_create()
  require(bus != 0UL, "event bus creation failed")
  let waiter = spawn_waiter(bus, wakeup_callback=noop_callback())
  if waiter == 0UL {
    event_bus_destroy(bus)
    abort("waiter creation failed")
  }
  terminate_waiter(waiter)
  event_bus_destroy(bus)
}

///|
fn main {
  let args = @env.args()
  guard args.length() == 2 else {
    abort("usage: metonic_waiter_handles EXPECTED_DELTA")
  }
  let expected_uint = @string.parse_uint(args[1]) catch {
    _ => abort("invalid expected delta")
  }
  require(expected_uint <= 32U, "expected delta must be between 0 and 32")
  let expected = expected_uint.reinterpret_as_int()

  ignore(@async.now())
  run_cycle()
  let before = process_handle_count()
  require(before >= 0, "GetProcessHandleCount failed before")
  for _ in 0..<32 {
    run_cycle()
  }
  let after = process_handle_count()
  require(after >= 0, "GetProcessHandleCount failed after")
  let delta = after - before
  require(
    delta == expected,
    "unexpected handle delta before=" +
    before.to_string() +
    " after=" +
    after.to_string() +
    " delta=" +
    delta.to_string(),
  )
  println(
    "RESULT {\"ok\":true,\"mode\":\"waiter_handles\",\"cycles\":32,\"before\":" +
    before.to_string() +
    ",\"after\":" +
    after.to_string() +
    ",\"delta\":" +
    delta.to_string() +
    "}",
  )
}
