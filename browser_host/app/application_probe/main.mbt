///|
priv struct Model {
  tree : @semantics.Tree
  add : @semantics.NodeRef
  mut inputs : Array[@semantics.NodeRef]
  mut serial : Int
  mut invalid : Int
  mut clipped : Bool
  list : @layout.VerticalList
  rows : Array[@semantics.NodeRef]
  operations : @operations.Model
  edits : Array[@app.TextEdit]
  mut edit_completed : Int
  publication_root : @reactive.Scope
  publication_registry : @reactive_task.PublicationRegistry
  publication_source : @reactive_task.Source[String, Int]
  publication_cycle : @reactive_task.Cycle
  publication_demand : @reactive.Signal[Int]
  publication : @reactive_task.Publication[Int, Int]
  publication_release : Ref[Bool]
}

///|
let active : Ref[Model?] = Ref(None)

///|
let task_control : Ref[@task.TaskControl?] = Ref(None)

///|
fn Model::change(self : Model, command : Int) -> Unit {
  match command {
    0 => {
      self.serial += 1
      self.inputs.push(
        @semantics.add_input(
          self.tree,
          "Input " + self.serial.to_string(),
          "value " + self.serial.to_string(),
        ).unwrap(),
      )
    }
    1 => {
      let reversed = []
      for i = self.inputs.length() - 1; i >= 0; i = i - 1 {
        reversed.push(self.inputs[i])
      }
      self.inputs = reversed
    }
    2 | 3 =>
      if self.inputs.length() > 0 {
        let removed = self.inputs[0]
        ignore(@semantics.remove(self.tree, removed))
        self.inputs = self.inputs.filter(reference => reference != removed)
        if command == 3 {
          self.inputs.push(
            @semantics.restore_input(
              self.tree,
              removed.id,
              "Replacement",
              "safe",
            ).unwrap(),
          )
        }
      }
    4 | 5 | 9 | 10 => self.invalid = command
    11 =>
      for reference in self.inputs {
        ignore(@semantics.set_text(self.tree, reference, "programmatic"))
      }
    12 => ignore(@semantics.set_button_value(self.tree, self.add, "updated"))
    13 => self.clipped = true
    14 => self.clipped = false
    15 => self.invalid = 15
    6 => {
      for reference in self.inputs {
        ignore(@semantics.remove(self.tree, reference))
      }
      self.inputs.clear()
    }
    7 | 8 =>
      for reference in self.inputs {
        ignore(@semantics.set_enabled(self.tree, reference, command == 8))
      }
    _ => ()
  }
}

///|
#export_name("change")
pub fn change(command : Int) -> Unit {
  if active.val is Some(model) {
    model.change(command)
  }
}

///|
#export_name("value")
pub fn value(index : Int) -> String {
  guard active.val is Some(model) && index >= 0 && index < model.inputs.length() else {
    return ""
  }
  @semantics.node(model.tree, model.inputs[index]).unwrap().value
}

///|
#export_name("operation_state")
pub fn operation_state(index : Int) -> Int {
  active.val.map(model => model.operations.state(index)).unwrap_or(-1)
}

///|
#export_name("operation_cancel")
pub fn operation_cancel() -> Bool {
  guard active.val is Some(model) && task_control.val is Some(control) else {
    return false
  }
  control.cancel(model.operations.slow_operation())
  true
}

///|
#export_name("create")
pub fn create() -> @host.Instance {
  let tree = @semantics.empty(901, 1)
  let publication_root = @reactive.Scope::root(@reactive.Graph::new())
  let publication_registry = @reactive_task.PublicationRegistry::new(
    publication_root,
  )
  let publication_source : @reactive_task.Source[String, Int] = @reactive_task.Source::new(
    publication_root,
  )
  let publication_cycle = @reactive_task.Cycle::new()
  let publication_demand = @reactive.Signal::new(publication_root, 0)
  let publication = publication_registry.register(publication_root, () => {
    (
      publication_demand.get(),
      publication_source.current("probe", publication_cycle),
    )
  })
  let model = Model::{
    tree,
    add: @semantics.add_button(tree, "Add input").unwrap(),
    inputs: [],
    serial: 0,
    invalid: 0,
    clipped: false,
    list: @layout.VerticalList::new(row_height=36, gap=4).unwrap(),
    rows: Array::makei(8, index => {
      @semantics.add_button(tree, "Row " + (index + 1).to_string()).unwrap()
    }),
    operations: @operations.create(() => @async.CondVar::Cond().wait(), tree~),
    edits: [],
    edit_completed: 0,
    publication_root,
    publication_registry,
    publication_source,
    publication_cycle,
    publication_demand,
    publication,
    publication_release: Ref(false),
  }
  active.val = Some(model)
  let app : @app.Application = {
    title: "Dynamic application probe",
    editor: tree,
    default_input: None,
    initial_size: (480, 400),
    viewport: Some({
      scroll: (x, y, delta) => {
        model.invalid == 15 && model.list.scroll_at(x, y, delta)
      },
      reveal: reference => model.invalid == 15 && model.list.reveal(reference),
    }),
    publications: Some(model.publication_registry),
    connect_tasks: control => {
      if task_control.val is Some(_) {
        abort("task control connected twice")
      }
      task_control.val = Some(control)
      if !model.publication_source.connect(control) {
        abort("publication probe source was not connected")
      }
    },
    initialize: () => {
      if task_control.val is None {
        abort("task control was not connected before initialize")
      }
      model.publication_source.replace(
        "probe",
        model.publication_cycle,
        false,
        () => {
          while !model.publication_release.val {
            @async.sleep(1)
          }
          7
        },
      )
    },
    view: () => {
      if model.invalid == 15 {
        let clip : @view.Bounds = { x: 16, y: 60, width: 180, height: 100, }
        model.list.arrange(clip, model.rows).unwrap()
        return model.list
          .items()
          .map(placement => {
            let node = @semantics.node(tree, placement.reference).unwrap()
            @app.Control::{
              element: {
                bounds: placement.bounds,
                text: node.name,
                reference: Some(node.reference),
                focused: node.focused,
              },
              kind: Button,
              clip: Some(clip),
            }
          })
      }
      if model.invalid == 9 {
        return (model.operations.application().view)()
      }
      let controls : Array[@app.Control] = [
        {
          element: {
            reference: Some(model.add),
            text: "Add input",
            focused: false,
            bounds: { x: 16, y: 8, width: 180, height: 40, },
          },
          kind: Button,
          clip: if model.clipped {
            Some({ x: 106, y: 8, width: 90, height: 40, })
          } else {
            None
          },
        },
      ]
      for index, reference in model.inputs {
        let node = @semantics.node(tree, reference).unwrap()
        controls.push({
          element: {
            reference: Some(reference),
            text: node.value,
            focused: node.focused,
            bounds: { x: 16, y: 60 + index * 100, width: 400, height: 80, },
          },
          kind: Input(single_line=model.invalid == 5 || model.invalid == 10),
          clip: None,
        })
      }
      if model.invalid == 4 && controls.length() > 1 {
        controls.push(controls[1])
      }
      let publication_label = match model.publication.get() {
        None => "Not published"
        Some(state) => {
          let phase = match state.current {
            @reactive_task.CurrentPending(_) => "Pending"
            @reactive_task.CurrentReady(value, _) =>
              "Ready " + value.to_string()
            @reactive_task.CurrentBlocked(_) => "Blocked"
            _ => "Other"
          }
          "Publication " + state.demand.to_string() + ": " + phase
        }
      }
      controls.push({
        element: {
          reference: None,
          text: publication_label,
          focused: false,
          bounds: { x: 270, y: 8, width: 200, height: 40, },
        },
        kind: Text,
        clip: None,
      })
      controls
    },
    activate: reference => {
      if model.invalid == 9 {
        return (model.operations.application().activate)(reference)
      }
      if reference == model.add {
        model.change(0)
        model.publication_demand.set(model.publication_demand.peek() + 1)
        ignore(@semantics.focus(tree, model.inputs[model.inputs.length() - 1]))
      }
      None
    },
    resize: (_, _) => true,
    stop: () => {
      model.publication_source.dispose()
      model.publication_root.dispose()
      ignore(@semantics.dispose(tree))
      (model.operations.application().stop)()
    },
    can_close: () => true,
    close_requested: () => (),
    close_ready: () => false,
    input_error: _ => (),
    edited: edit => {
      model.edits.push(edit)
      Some(
        @task.replace(
          () => (),
          () => {
            Some(
              @task.work(() => (), _ => {
                model.edit_completed += 1
                @task.Unchanged
              }),
            )
          },
          operation=@task.Operation::new(),
        ),
      )
    },
    dispose: () => (model.operations.application().dispose)(),
  }
  @host.create(
    app,
    [],
    root_id=Some("controls"),
    canvas_id="canvas",
    event_name="metonic-notes",
    font_url="./NotoSansJP.ttf",
    font_sha256="c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f",
  )
}

///|
#export_name("publication_phase")
pub fn publication_phase() -> Int {
  guard active.val is Some(model) else { return -1 }
  match model.publication.get() {
    None => 0
    Some(state) =>
      match state.current {
        @reactive_task.CurrentPending(_) => 1
        @reactive_task.CurrentReady(_, _) => 2
        @reactive_task.CurrentBlocked(_) => 3
        _ => 4
      }
  }
}

///|
#export_name("publication_source_phase")
pub fn publication_source_phase() -> Int {
  guard active.val is Some(model) else { return -1 }
  match model.publication_source.peek() {
    @reactive_task.Idle => 0
    @reactive_task.Pending(_, _, _) => 1
    @reactive_task.Ready(_, _, _, _) => 2
    @reactive_task.Failed(_, _, _, _) => 3
    @reactive_task.Canceled(_, _, _) => 4
  }
}

///|
#export_name("publication_demand")
pub fn publication_demand() -> Int {
  active.val.map(model => model.publication.get().unwrap().demand).unwrap_or(-1)
}

///|
#export_name("publication_release")
pub fn publication_release() -> Unit {
  if active.val is Some(model) {
    model.publication_release.val = true
  }
}

///|
#export_name("edit_count")
pub fn edit_count() -> Int {
  active.val.map(model => model.edits.length()).unwrap_or(0)
}

///|
#export_name("edit_completed")
pub fn edit_completed() -> Int {
  active.val.map(model => model.edit_completed).unwrap_or(0)
}

///|
#export_name("edit_text")
pub fn edit_text() -> String {
  guard active.val is Some(model) && !model.edits.is_empty() else { return "" }
  model.edits[model.edits.length() - 1].text
}
