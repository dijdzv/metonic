///|
priv struct Diagnostics {
  mut frames : Int
  mut rejected_updates : Int
}

///|
fn Diagnostics::new() -> Diagnostics {
  { frames: 0, rejected_updates: 0, }
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
