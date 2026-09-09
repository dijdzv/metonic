///|
pub struct InputObservation {
  key_presses : Int
  pointer_presses : Int
  last_key : String
  pointer_x : Int?
  pointer_y : Int?
  focused : Bool?
} derive(ToJson)

///|
priv struct Diagnostics {
  mut input : InputObservation
  mut frames : Int
  mut rejected_updates : Int
  mut ime_events : Array[Json]
  mut ime_sequence : Int64
  mut ime_dropped : Int64
}

///|
extern "C" fn native_ime_trace_get(
  hwnd : UInt64,
  row : Int,
  column : Int,
) -> Int64 = "mbw_ime_trace_get"

///|
extern "C" fn native_tick_count() -> UInt64 = "GetTickCount64"

///|
fn App::raw_ime_events(self : App) -> Array[Json] {
  if self.window is None {
    return []
  }
  let total = native_ime_trace_get(self.hwnd, -1, 0)
  let result : Array[Json] = []
  for row = 0; row < total.min(128L).to_int(); row = row + 1 {
    result.push({
      "sequence": native_ime_trace_get(self.hwnd, row, 0),
      "tick_ms": native_ime_trace_get(self.hwnd, row, 1),
      "message": native_ime_trace_get(self.hwnd, row, 2),
      "flags": native_ime_trace_get(self.hwnd, row, 3),
      "cursor_queried": native_ime_trace_get(self.hwnd, row, 4) == 1L,
      "cursor_result": native_ime_trace_get(self.hwnd, row, 5),
    })
  }
  result
}

///|
fn App::raw_ime_dropped(self : App) -> Int64 {
  if self.window is None {
    return 0L
  }
  (native_ime_trace_get(self.hwnd, -1, 0) - 128L).max(0L)
}

///|
fn Diagnostics::new() -> Diagnostics {
  {
    frames: 0,
    rejected_updates: 0,
    ime_events: [],
    ime_sequence: 0L,
    ime_dropped: 0L,
    input: {
      key_presses: 0,
      pointer_presses: 0,
      last_key: "none",
      pointer_x: None,
      pointer_y: None,
      focused: None,
    },
  }
}

///|
fn Diagnostics::observe_input(
  self : Diagnostics,
  event : @core.WindowEvent,
) -> Unit {
  match event {
    @core.WindowEvent::KeyboardInput(_, key, _) if key.state()
      is @core.ElementState::Pressed => {
      let kind = match key.logical_key() {
        @core.Key::Character(_) => "character"
        @core.Key::Named(@core.NamedKey::Tab) => "tab"
        @core.Key::Named(@core.NamedKey::Enter) => "enter"
        @core.Key::Named(@core.NamedKey::Backspace) => "backspace"
        @core.Key::Named(@core.NamedKey::ArrowLeft) => "left"
        @core.Key::Named(@core.NamedKey::ArrowRight) => "right"
        @core.Key::Named(@core.NamedKey::ArrowUp) => "up"
        @core.Key::Named(@core.NamedKey::ArrowDown) => "down"
        _ => "other"
      }
      self.input = {
        ..self.input,
        key_presses: self.input.key_presses.min(2147483646) + 1,
        last_key: kind,
      }
    }
    @core.WindowEvent::PointerButton(
      _,
      @core.ElementState::Pressed,
      position,
      _,
      _
    ) =>
      self.input = {
        ..self.input,
        pointer_presses: self.input.pointer_presses.min(2147483646) + 1,
        pointer_x: Some(position.x().to_int()),
        pointer_y: Some(position.y().to_int()),
      }
    @core.WindowEvent::Focused(value) =>
      self.input = { ..self.input, focused: Some(value), }
    _ => ()
  }
}

///|
fn Diagnostics::presented(self : Diagnostics) -> Unit {
  self.frames += 1
}

///|
fn Hooks::processed(_self : Hooks, event : Event, app : App) -> Unit {
  let (kind, supplied, length) : (String, Int?, Int) = match event {
    CompositionStart => ("start", None, 0)
    CompositionUpdate(value, cursor) => ("update", cursor, value.length())
    CompositionCancel => ("cancel", None, 0)
    Commit(value) => ("commit", None, value.length())
    _ => return
  }
  let diagnostics = app.diagnostics
  diagnostics.ime_sequence += 1L
  if diagnostics.ime_events.length() == 128 {
    let retained : Array[Json] = []
    for i = 1; i < diagnostics.ime_events.length(); i = i + 1 {
      retained.push(diagnostics.ime_events[i])
    }
    diagnostics.ime_events = retained
    diagnostics.ime_dropped += 1L
  }
  let node = app.input_node()
  let applied : Int? = if app.composition is Some(_) {
    Some(app.preedit_cursor)
  } else {
    None
  }
  diagnostics.ime_events.push({
    "sequence": diagnostics.ime_sequence,
    "tick_ms": native_tick_count(),
    "kind": kind,
    "field": if node.reference == app.model.query_input {
      "query"
    } else {
      "editor"
    },
    "utf16_length": length,
    "supplied_cursor": match supplied {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "applied_cursor": match applied {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "selection_start": node.selection_start,
    "selection_end": node.selection_end,
    "composing": app.composition is Some(_),
  })
}

///|
fn Diagnostics::rejected(self : Diagnostics) -> Unit {
  self.rejected_updates += 1
}

///|
priv struct Hooks {
  observer : (async (Observation) -> Unit)?
  completed : ((Observation) -> Unit raise Error)?
  lifecycle : ((Lifecycle, Observation) -> Bool raise Error)?
  controller : (async (Handle) -> Unit)?
}

///|
pub async fn run(
  observer? : (async (Observation) -> Unit)? = None,
  completed? : ((Observation) -> Unit raise Error)? = None,
  lifecycle? : ((Lifecycle, Observation) -> Bool raise Error)? = None,
  controller? : (async (Handle) -> Unit)? = None,
  hidden? : Bool = false,
  report? : (String) -> Unit = println,
) -> Unit {
  run_loop({ observer, completed, lifecycle, controller, }, hidden, report)
}

///|
fn Hooks::has_lifecycle(self : Hooks) -> Bool {
  self.lifecycle is Some(_)
}

///|
fn Hooks::has_controller(self : Hooks) -> Bool {
  self.controller is Some(_)
}

///|
fn Hooks::notify(
  self : Hooks,
  phase : Lifecycle,
  app : App,
) -> Bool raise Error {
  match self.lifecycle {
    Some(notify) => notify(phase, app.observation())
    None => true
  }
}

///|
async fn Hooks::control(self : Hooks, app : App) -> Unit {
  if self.controller is Some(control) {
    control(app.handle())
  }
}

///|
async fn Hooks::observe(self : Hooks, app : App) -> Unit {
  if self.observer is Some(observe) {
    observe(app.observation())
  }
}

///|
fn Hooks::complete(self : Hooks, app : App) -> Unit raise Error {
  if self.completed is Some(complete) {
    complete(app.observation())
  }
}
