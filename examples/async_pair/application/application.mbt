///|
priv struct PairDemo {
  graph : @reactive.Graph
  scope : @reactive.Scope
  selected : @reactive.Signal[String]
  cycle : @reactive.Signal[@async_state.Cycle]
  detail : @async_state.Source[String, String]
  related : @async_state.Source[String, String]
  view_state : @reactive.Memo[@async_state.PairView[String, String, String]]
  tree : @semantics.Tree
  buttons : Array[@semantics.NodeRef]
  wait : async (Int) -> Unit
  mut attempt : Int
  mut size : (Int, Int)
  mut error : String?
}

///|
fn PairDemo::request(
  self : PairDemo,
  key : String,
  retain_previous : Bool,
) -> @task.Request? {
  let cycle = @async_state.Cycle::new()
  let next_attempt = if key == "two" { self.attempt + 1 } else { self.attempt }
  let left = self.detail.replace(key, cycle, retain_previous, () => {
    (self.wait)(250)
    "Detail " + key
  })
  let right = self.related.replace_result(
    key,
    cycle,
    retain_previous,
    async fn() -> Result[String, String] {
      (self.wait)(700)
      if key == "two" && next_attempt == 1 {
        Err("related data unavailable")
      } else {
        Ok("Related " + key)
      }
    },
    error => error,
  )
  guard (left, right) is (Some(left), Some(right)) else { return None }
  Some(
    @task.group([left, right], apply => self.graph.batch(apply), on_admitted=() => {
      self.attempt = next_attempt
      self.selected.set(key)
      self.cycle.set(cycle)
    }),
  )
}

///|
fn PairDemo::cancel(self : PairDemo) -> @task.Request? {
  guard (self.detail.cancel(), self.related.cancel())
    is (Some(left), Some(right)) else {
    return None
  }
  Some(@task.group([left, right], apply => self.graph.batch(apply)))
}

///|
fn status(view : @async_state.PairView[String, String, String]) -> String {
  match view {
    PairIdle => "Idle"
    PairPending(key, _, Some(previous)) =>
      "Refreshing " + key + ": " + previous.left + " / " + previous.right
    PairPending(key, _, None) => "Loading " + key
    PairReady(key, _, detail, related) =>
      "Ready " + key + ": " + detail + " / " + related
    PairFailed(key, _, failure, Some(previous)) =>
      "Failed " +
      key +
      ": " +
      failure_text(failure) +
      " (previous " +
      previous.left +
      " / " +
      previous.right +
      ")"
    PairFailed(key, _, failure, None) =>
      "Failed " + key + ": " + failure_text(failure)
    PairCanceled(key, _, _) => "Canceled " + key
  }
}

///|
fn failure_text(failure : @async_state.PairFailure) -> String {
  match failure {
    Left(message) | Right(message) => message
    Both(left, right) => left + "; " + right
  }
}

///|
fn PairDemo::view(self : PairDemo) -> Array[@app.Control] {
  let width = self.size.0
  let controls : Array[@app.Control] = []
  let labels = ["One", "Two", "Refresh", "Retry", "Cancel"]
  for index, reference in self.buttons {
    let node = @semantics.node(self.tree, reference).unwrap()
    controls.push({
      element: {
        bounds: { x: 16 + index * 100, y: 16, width: 92, height: 36, },
        text: labels[index],
        reference: Some(reference),
        focused: node.focused,
      },
      kind: @app.Button,
      clip: None,
    })
  }
  controls.push({
    element: {
      bounds: { x: 16, y: 68, width: (width - 32).max(32), height: 100, },
      text: status(self.view_state.get()),
      reference: None,
      focused: false,
    },
    kind: @app.Text,
    clip: None,
  })
  if self.error is Some(error) {
    controls.push({
      element: {
        bounds: { x: 16, y: 180, width: (width - 32).max(32), height: 40, },
        text: error,
        reference: None,
        focused: false,
      },
      kind: @app.Text,
      clip: None,
    })
  }
  controls
}

///|
pub fn create(wait : async (Int) -> Unit) -> @app.Application {
  let graph = @reactive.Graph::new()
  let scope = @reactive.Scope::root(graph)
  let selected = @reactive.Signal::new(scope, "one")
  let cycle = @reactive.Signal::new(scope, @async_state.Cycle::new())
  let detail : @async_state.Source[String, String] = @async_state.Source::new(
    scope,
  )
  let related : @async_state.Source[String, String] = @async_state.Source::new(
    scope,
  )
  let view_state = @reactive.Memo::new(scope, () => {
    @async_state.derive_pair(
      selected.get(),
      cycle.get(),
      detail.get(),
      related.get(),
    )
  })
  let tree = @semantics.empty(1, 1)
  let buttons = ["One", "Two", "Refresh", "Retry", "Cancel"].map(name => {
    @semantics.add_button(tree, name).unwrap()
  })
  let model : PairDemo = {
    graph,
    scope,
    selected,
    cycle,
    detail,
    related,
    view_state,
    tree,
    buttons,
    wait,
    attempt: 0,
    size: (560, 240),
    error: None,
  }
  {
    title: "Async pair",
    editor: tree,
    default_input: None,
    initial_size: model.size,
    viewport: None,
    publications: None,
    connect_tasks: control => {
      if !model.detail.connect(control) || !model.related.connect(control) {
        abort("async pair task connection failed")
      }
    },
    initialize: () => model.request("one", false),
    view: () => model.view(),
    activate: reference => {
      if reference == model.buttons[0] {
        model.request("one", false)
      } else if reference == model.buttons[1] {
        model.request("two", false)
      } else if reference == model.buttons[2] || reference == model.buttons[3] {
        model.request(model.selected.peek(), true)
      } else if reference == model.buttons[4] {
        model.cancel()
      } else {
        None
      }
    },
    edited: _ => None,
    resize: (width, height) => {
      if width < 520 || height < 220 {
        return false
      }
      let changed = model.size != (width, height)
      model.size = (width, height)
      changed
    },
    stop: () => (),
    can_close: () => true,
    close_requested: () => (),
    close_ready: () => false,
    input_error: error => model.error = error,
    dispose: () => model.scope.dispose(),
  }
}
