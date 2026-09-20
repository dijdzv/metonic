///|
priv enum TaskGate {
  Always
  PointerIdle
  CommittedInput
}

///|
fn App::movement_request(self : App) -> Event {
  ApplicationTask(@p0_tasks.movement(self.model), PointerIdle)
}

///|
fn App::user_request(self : App, value : String) -> Event {
  ApplicationTask(@p0_tasks.user(self.model, value), CommittedInput)
}

///|
fn App::cancel_request(self : App) -> Event {
  ApplicationTask(@p0_tasks.cancel(self.model), Always)
}
