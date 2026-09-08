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
}

///|
fn Diagnostics::new() -> Diagnostics {
  {
    frames: 0,
    rejected_updates: 0,
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
