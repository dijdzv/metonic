///|
priv struct Diagnostics {}

///|
fn Diagnostics::observe_input(
  _self : Diagnostics,
  _event : @core.WindowEvent,
) -> Unit {
  ()
}

///|
fn Diagnostics::new() -> Diagnostics {
  Diagnostics::{ }
}

///|
fn Diagnostics::presented(_self : Diagnostics) -> Unit {
  ()
}

///|
fn Diagnostics::rejected(_self : Diagnostics) -> Unit {
  ()
}

///|
priv struct Hooks {}

///|
fn Hooks::processed(_self : Hooks, _event : Event, _app : App) -> Unit {
  ()
}

///|
type DevelopmentRequest = Unit

///|
pub async fn run(
  application : @host_application.Application,
  hidden? : Bool = false,
  minimum_size? : (Int, Int)? = None,
  font_path? : String? = None,
  report? : (String) -> Unit = println,
) -> Unit {
  run_loop(application, Hooks::{ }, hidden, minimum_size, font_path, report)
}

///|
fn Hooks::has_lifecycle(_self : Hooks) -> Bool {
  false
}

///|
fn Hooks::has_controller(_self : Hooks) -> Bool {
  false
}

///|
fn Hooks::notify(_self : Hooks, _phase : Lifecycle, _app : App) -> Bool {
  true
}

///|
fn Hooks::control(_self : Hooks, _app : App) -> Unit {
  ()
}

///|
fn Hooks::observe(_self : Hooks, _app : App) -> Unit {
  ()
}

///|
fn Hooks::complete(_self : Hooks, _app : App) -> Unit {
  ()
}

///|
fn App::dispatch_development(
  _self : App,
  _request : DevelopmentRequest,
) -> Unit {
  ()
}
