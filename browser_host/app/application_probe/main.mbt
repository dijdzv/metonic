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
  keyed : @component.KeyedChildren[Int, String, @semantics.NodeRef]
  mut keyed_mode : Bool
  keyed_created : Ref[Int]
  keyed_disposed : Ref[Int]
  publication_registry : @reactive_task.PublicationRegistry
  downstream_registry : @reactive_task.DownstreamRegistry
  serial_registry : @reactive_task.SerialRegistry
  serial_writer : @reactive_task.SerialTask[Int, String, String]
  serial_release : Ref[Bool]
  serial_started : Array[Int]
  serial_applied : Array[Int]
  publication_source : @reactive_task.Source[String, Int]
  publication_cycle : @reactive_task.Cycle
  publication_demand : @reactive.Signal[Int]
  downstream_key : @reactive.Signal[String]
  publication : @reactive_task.Publication[Int, Int]
  downstream_publication : @reactive_task.Publication[Int, Int]
  publication_release : Ref[Bool]
  downstream_release : Ref[Bool]
  downstream_cleanup : Ref[Int]
  ui : @component.UiRoot
  controlled : @reactive.Signal[String]
  controlled_input : Ref[@semantics.NodeRef?]
  controlled_button : Ref[@semantics.NodeRef?]
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
    16 => self.downstream_key.set("other")
    17 => self.downstream_key.set("probe")
    18 => self.invalid = 18
    30 => {
      self.invalid = 30
      if self.controlled_input.val is None {
        self.controlled_input.val = self.ui
          .fixed("controlled")
          .text_input(
            "value",
            "Controlled",
            @component.Controlled::new(() => self.controlled.peek(), text => {
              self.controlled.set(text)
              None
            }),
          )
          .map(input => input.reference())
      }
      if self.controlled_button.val is None {
        self.controlled_button.val = self.ui
          .fixed("controlled")
          .button("async", "Update async", () => {
            Some(
              @task.replace(
                () => (),
                () => {
                  Some(
                    @task.work(() => "async", value => {
                      self.controlled.set(value)
                      @task.Changed
                    }),
                  )
                },
                operation=@task.Operation::new(),
              ),
            )
          })
          .map(button => button.reference())
      }
    }
    31 => self.controlled.set("programmatic")
    32 => self.controlled.set("deferred")
    20 => {
      self.keyed_mode = true
      self.update_keyed([{ key: 1, props: "One", }, { key: 2, props: "Two", }])
    }
    21 =>
      self.update_keyed([{ key: 2, props: "Two", }, { key: 1, props: "One", }])
    22 => self.update_keyed([{ key: 2, props: "Two", }])
    23 =>
      self.update_keyed([{ key: 2, props: "Two", }, { key: 1, props: "One", }])
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
fn Model::update_keyed(
  self : Model,
  specs : Array[@component.ChildSpec[Int, String]],
) -> Unit {
  ignore(
    self.keyed.reconcile(
      specs,
      (owner, _, label) => {
        self.keyed_created.val += 1
        owner.scope().on_dispose(() => self.keyed_disposed.val += 1)
        owner.add_input(label, "abc").unwrap()
      },
      (reference, label) => {
        ignore(@semantics.set_name(self.tree, reference, label))
      },
    ),
  )
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
#export_name("controlled_value")
pub fn controlled_value() -> String {
  active.val.map(model => model.controlled.peek()).unwrap_or("")
}

///|
#export_name("create")
pub fn create() -> @host.Instance {
  let tree = @semantics.empty(901, 1)
  let publication_root = @reactive.Scope::root(@reactive.Graph::new())
  let ui = @component.UiRoot::new(publication_root, tree)
  let controlled = @reactive.Signal::new(publication_root, "initial")
  let controlled_input : Ref[@semantics.NodeRef?] = Ref(None)
  let controlled_button : Ref[@semantics.NodeRef?] = Ref(None)
  let keyed : @component.KeyedChildren[Int, String, @semantics.NodeRef] = @component.KeyedChildren::new(
    publication_root, tree,
  )
  let publication_registry = @reactive_task.PublicationRegistry::new(
    publication_root,
  )
  let downstream_registry = @reactive_task.DownstreamRegistry::new(
    publication_root,
  )
  let serial_registry = @reactive_task.SerialRegistry::new(publication_root)
  let serial_release = Ref(false)
  let serial_started : Array[Int] = []
  let serial_applied : Array[Int] = []
  let serial_writer : @reactive_task.SerialTask[Int, String, String] = serial_registry.register(
    publication_root,
    async fn(value : String) {
      let identity = if value == "first" { 1 } else { 2 }
      serial_started.push(identity)
      if identity == 1 {
        while !serial_release.val {
          @async.sleep(1)
        }
      }
      Ok(value)
    },
    (job, result) => {
      if !(result is Ok(_)) {
        abort("serial write failed")
      }
      serial_applied.push(job.identity)
    },
  )
  let publication_source : @reactive_task.Source[String, Int] = @reactive_task.Source::new(
    publication_root,
  )
  let publication_cycle = @reactive_task.Cycle::new()
  let publication_demand = @reactive.Signal::new(publication_root, 0)
  let downstream_key = @reactive.Signal::new(publication_root, "probe")
  let downstream_release = Ref(false)
  let downstream_cleanup = Ref(0)
  let publication = publication_registry.register(publication_root, () => {
    (
      publication_demand.get(),
      publication_source.current("probe", publication_cycle),
    )
  })
  let downstream = downstream_registry.register(
    publication_root,
    () => publication_source.current(downstream_key.get(), publication_cycle),
    async fn(value : Int) {
      defer {
        downstream_cleanup.val += 1
      }
      while !downstream_release.val {
        @async.sleep(1)
      }
      value * 2
    },
  )
  let downstream_publication = publication_registry.register(publication_root, () => {
    (publication_demand.get(), downstream.current())
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
    keyed,
    keyed_mode: false,
    keyed_created: Ref(0),
    keyed_disposed: Ref(0),
    publication_registry,
    downstream_registry,
    serial_registry,
    serial_writer,
    serial_release,
    serial_started,
    serial_applied,
    publication_source,
    publication_cycle,
    publication_demand,
    downstream_key,
    publication,
    downstream_publication,
    publication_release: Ref(false),
    downstream_release,
    downstream_cleanup,
    ui,
    controlled,
    controlled_input,
    controlled_button,
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
    downstreams: Some(model.downstream_registry),
    serials: Some(model.serial_registry),
    components: Some(ui),
    connect_tasks: control => {
      if task_control.val is Some(_) {
        abort("task control connected twice")
      }
      task_control.val = Some(control)
      if !model.publication_source.connect(control) {
        abort("publication probe source was not connected")
      }
      if !model.downstream_registry.connect(control) {
        abort("downstream probe registry was not connected")
      }
      if !model.serial_registry.connect(control) {
        abort("serial probe registry was not connected")
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
      if model.invalid == 30 && model.controlled_input.val is Some(reference) {
        let node = @semantics.node(tree, reference).unwrap()
        let controls : Array[@app.Control] = [
          {
            element: {
              reference: Some(reference),
              text: node.value,
              focused: node.focused,
              bounds: { x: 16, y: 60, width: 400, height: 60, },
            },
            kind: Input(single_line=true),
            clip: None,
          },
        ]
        if model.controlled_button.val is Some(button) {
          controls.push({
            element: {
              reference: Some(button),
              text: "Update async",
              focused: @semantics.node(tree, button).unwrap().focused,
              bounds: { x: 16, y: 130, width: 180, height: 40, },
            },
            kind: Button,
            clip: None,
          })
        }
        return controls
      }
      if model.keyed_mode {
        let references = model.keyed.ordered()
        return Array::makei(references.length(), index => {
          let reference = references[index]
          let node = @semantics.node(tree, reference).unwrap()
          @app.Control::{
            element: {
              reference: Some(reference),
              text: node.value,
              focused: node.focused,
              bounds: { x: 16, y: 32 + index * 70, width: 300, height: 60, },
            },
            kind: Input(single_line=true),
            clip: None,
          }
        })
      }
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
      controls.push({
        element: {
          reference: None,
          text: match model.downstream_publication.get() {
            Some(state) =>
              match state.current {
                @reactive_task.CurrentReady(value, _) =>
                  "Downstream " + value.to_string()
                @reactive_task.CurrentPending(_) => "Downstream pending"
                @reactive_task.CurrentBlocked(_) => "Downstream blocked"
                _ => "Downstream other"
              }
            None => "Downstream not published"
          },
          focused: false,
          bounds: { x: 270, y: 48, width: 200, height: 40, },
        },
        kind: Text,
        clip: None,
      })
      controls
    },
    activate: reference => {
      if model.controlled_button.val == Some(reference) {
        return ui.activate(reference)
      }
      if model.invalid == 9 {
        return (model.operations.application().activate)(reference)
      }
      if reference == model.add {
        if model.invalid == 18 &&
          (
            !model.serial_writer.enqueue(1, "first") ||
            !model.serial_writer.enqueue(2, "second")
          ) {
          abort("serial probe writes were not queued")
        }
        model.change(0)
        model.publication_demand.set(model.publication_demand.peek() + 1)
        ignore(@semantics.focus(tree, model.inputs[model.inputs.length() - 1]))
      }
      None
    },
    resize: (_, _) => true,
    stop: () => {
      ignore(model.keyed.clear())
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
      if model.controlled_input.val == Some(edit.target) {
        return ui.edited(edit.target, edit.text, edit.revision)
      }
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
#export_name("downstream_phase")
pub fn downstream_phase() -> Int {
  guard active.val is Some(model) else { return -1 }
  match model.downstream_publication.get() {
    None => 0
    Some(state) =>
      match state.current {
        @reactive_task.CurrentPending(_) => 1
        @reactive_task.CurrentReady(14, _) => 2
        @reactive_task.CurrentBlocked(_) => 3
        _ => 4
      }
  }
}

///|
#export_name("downstream_release")
pub fn downstream_release() -> Unit {
  if active.val is Some(model) {
    model.downstream_release.val = true
  }
}

///|
#export_name("downstream_cleanup")
pub fn downstream_cleanup() -> Int {
  active.val.map(model => model.downstream_cleanup.val).unwrap_or(-1)
}

///|
#export_name("serial_started")
pub fn serial_started() -> Int {
  active.val.map(model => model.serial_started.length()).unwrap_or(-1)
}

///|
#export_name("serial_applied")
pub fn serial_applied() -> Int {
  active.val.map(model => model.serial_applied.length()).unwrap_or(-1)
}

///|
#export_name("serial_active")
pub fn serial_active() -> Int {
  guard active.val is Some(model) else { return -1 }
  model.serial_writer.snapshot().active.map(job => job.identity).unwrap_or(0)
}

///|
#export_name("serial_queued")
pub fn serial_queued() -> Int {
  active.val
  .map(model => model.serial_writer.snapshot().queued.length())
  .unwrap_or(-1)
}

///|
#export_name("serial_release")
pub fn serial_release() -> Unit {
  if active.val is Some(model) {
    model.serial_release.val = true
  }
}

///|
#export_name("keyed_created")
pub fn keyed_created() -> Int {
  active.val.map(model => model.keyed_created.val).unwrap_or(-1)
}

///|
#export_name("keyed_disposed")
pub fn keyed_disposed() -> Int {
  active.val.map(model => model.keyed_disposed.val).unwrap_or(-1)
}

///|
#export_name("keyed_generation")
pub fn keyed_generation(key : Int) -> Int {
  guard active.val is Some(model) && model.keyed.get(key) is Some(reference) else {
    return -1
  }
  reference.generation
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
