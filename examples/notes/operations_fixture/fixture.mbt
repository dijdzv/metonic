///|
pub struct Model {
  tree : @semantics.Tree
  buttons : Array[@semantics.NodeRef]
  slow : @task.Operation
  other : @task.Operation
  wait : async () -> Unit
  mut status : Int
  mut completed : Int
  mut failures : Int
  mut cleaned : Int
  mut disposed : Int
  mut cancellations : Int
  mut starts : Int
}

///|
pub fn create(
  wait : async () -> Unit,
  tree? : @semantics.Tree = @semantics.empty(930, 1),
) -> Model {
  {
    tree,
    buttons: ["Start slow", "Run other", "Cancel slow", "Fail work"].map(name => {
      @semantics.add_button(tree, name).unwrap()
    }),
    slow: @task.Operation::new(),
    other: @task.Operation::new(),
    wait,
    status: 0,
    completed: 0,
    failures: 0,
    cleaned: 0,
    disposed: 0,
    cancellations: 0,
    starts: 0,
  }
}

///|
pub fn Model::state(self : Model, index : Int) -> Int {
  match index {
    0 => self.status
    1 => self.completed
    2 => self.failures
    3 => self.cleaned
    4 => self.disposed
    5 => self.cancellations
    6 => self.starts
    _ => -1
  }
}

///|
pub fn Model::slow_operation(self : Model) -> @task.Operation {
  self.slow
}

///|
suberror FixtureFailure derive(Debug)

///|
pub fn Model::application(self : Model) -> @app.Application {
  {
    title: "Independent operations",
    editor: self.tree,
    default_input: None,
    initial_size: (480, 320),
    viewport: None,
    connect_tasks: _ => (),
    publications: None,
    downstreams: None,
    initialize: () => None,
    view: () => {
      let controls : Array[@app.Control] = []
      for index, reference in self.buttons {
        let node = @semantics.node(self.tree, reference).unwrap()
        controls.push({
          element: {
            reference: Some(reference),
            text: node.name,
            focused: node.focused,
            bounds: { x: 16, y: 16 + index * 50, width: 240, height: 40, },
          },
          kind: Button,
          clip: None,
        })
      }
      controls
    },
    activate: reference => {
      if reference == self.buttons[0] {
        Some(
          @task.replace(
            () => (),
            () => {
              self.starts += 1
              self.status = 1
              Some(
                @task.work(
                  () => {
                    defer {
                      self.cleaned += 1
                    }
                    (self.wait)()
                  },
                  _ => {
                    self.status = 2
                    @task.Changed
                  },
                ),
              )
            },
            operation=self.slow,
          ),
        )
      } else if reference == self.buttons[1] {
        Some(
          @task.replace(
            () => (),
            () => {
              Some(
                @task.work(() => (), _ => {
                  self.completed += 1
                  @task.Changed
                }),
              )
            },
            operation=self.other,
          ),
        )
      } else if reference == self.buttons[2] {
        Some(
          @task.cancel(
            () => {
              self.cancellations += 1
              self.status = 3
            },
            operation=self.slow,
          ),
        )
      } else if reference == self.buttons[3] {
        Some(
          @task.replace(
            () => (),
            () => {
              Some(
                @task.work(fn() -> Unit raise { raise FixtureFailure }, _ => {
                  @task.Unchanged
                }),
              )
            },
            operation=self.other,
            on_failure=_ => {
              self.failures += 1
              @task.Changed
            },
          ),
        )
      } else {
        None
      }
    },
    resize: (_, _) => true,
    stop: () => ignore(@semantics.dispose(self.tree)),
    can_close: () => true,
    close_requested: () => (),
    close_ready: () => false,
    input_error: _ => (),
    edited: _ => None,
    dispose: () => self.disposed += 1,
  }
}
