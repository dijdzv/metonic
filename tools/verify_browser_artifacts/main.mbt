///|
#external
pub type BrowserApi

///|
extern "js" fn api_init(api : BrowserApi) -> Unit =
  #| (api) => api.init()

///|
extern "js" fn api_resize(api : BrowserApi, width : Int, height : Int) -> Int =
  #| (api, width, height) => api.resize(width, height)

///|
extern "js" fn api_move(api : BrowserApi, x : Int, y : Int) -> Int =
  #| (api, x, y) => api.move_to(x, y)

///|
extern "js" fn api_activate(api : BrowserApi) -> Unit =
  #| (api) => api.activate()

///|
extern "js" fn api_field(api : BrowserApi, index : Int) -> Int =
  #| (api, index) => api.field(index)

///|
extern "js" fn api_has_function(api : BrowserApi, name : String) -> Bool =
  #| (api, name) => typeof api[name] === "function"

///|
extern "js" fn throw_failure(message : String) -> Unit =
  #| (message) => { throw new Error(message); }

///|
pub suberror VerifyFailure {
  Failure(String)
}

///|
fn check_state(
  actual : Array[Int],
  expected : Array[Int],
) -> Unit raise VerifyFailure {
  if actual != expected {
    raise Failure("browser state mismatch")
  }
}

///|
fn snapshot(api : BrowserApi) -> Array[Int] {
  let values : Array[Int] = []
  for index = 0; index < 8; index = index + 1 {
    values.push(api_field(api, index))
  }
  values
}

///|
fn run(api : BrowserApi) -> Array[Array[Int]] raise VerifyFailure {
  let history : Array[Array[Int]] = []
  api_init(api)
  let initial = snapshot(api)
  check_state(initial, [260, 144, 120, 72, 0, 0, 640, 360])
  history.push(initial)
  if api_resize(api, 100, 50) != 1 {
    raise Failure("resize rejected")
  }
  let resized = snapshot(api)
  check_state(resized, [0, 0, 100, 50, 0, 1, 100, 50])
  history.push(resized)
  if api_move(api, -100, 1000) != 0 {
    raise Failure("invalid move accepted")
  }
  let unchanged = snapshot(api)
  check_state(unchanged, resized)
  history.push(unchanged)
  if api_resize(api, 640, 360) != 1 {
    raise Failure("resize rejected")
  }
  let viewport = snapshot(api)
  check_state(viewport, [0, 0, 120, 72, 0, 2, 640, 360])
  history.push(viewport)
  if api_move(api, 5000, 5000) != 1 {
    raise Failure("clamped move rejected")
  }
  let moved = snapshot(api)
  check_state(moved, [520, 288, 120, 72, 0, 3, 640, 360])
  history.push(moved)
  api_activate(api)
  let active = snapshot(api)
  check_state(active, [520, 288, 120, 72, 1, 4, 640, 360])
  history.push(active)
  if api_move(api, 5000, 5000) != 0 {
    raise Failure("unchanged move accepted")
  }
  let stable = snapshot(api)
  check_state(stable, active)
  history.push(stable)
  api_init(api)
  let reset = snapshot(api)
  check_state(reset, [260, 144, 120, 72, 0, 0, 640, 360])
  history.push(reset)
  history
}

///|
fn verify_checked(
  js : BrowserApi,
  wasm : BrowserApi,
) -> Unit raise VerifyFailure {
  for name in ["init", "resize", "move_to", "activate", "field"] {
    if !api_has_function(js, name) || !api_has_function(wasm, name) {
      raise Failure("missing browser export: " + name)
    }
  }
  let js_history = run(js)
  let wasm_history = run(wasm)
  if js_history != wasm_history {
    raise Failure("browser histories differ")
  }
}

///|
/// Compare the JavaScript and WasmGC browser APIs using the same concrete sequence.
#export_name("verify")
pub fn verify(js : BrowserApi, wasm : BrowserApi) -> Unit {
  verify_checked(js, wasm) catch {
    Failure(message) => throw_failure(message)
  }
}
