///|
priv struct Model {
  tree : @semantics.Tree
  add : @semantics.NodeRef
  mut inputs : Array[@semantics.NodeRef]
  mut serial : Int
  mut invalid : Int
  operations : @operations.Model
}

///|
let active : Ref[Model?] = Ref(None)

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
    4 | 5 | 9 => self.invalid = command
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
#export_name("create")
pub fn create() -> @host.Instance {
  let tree = @semantics.empty(901, 1)
  let model = Model::{
    tree,
    add: @semantics.add_button(tree, "Add input").unwrap(),
    inputs: [],
    serial: 0,
    invalid: 0,
    operations: @operations.create(() => @async.CondVar::Cond().wait(), tree~),
  }
  active.val = Some(model)
  let app : @app.Application = {
    title: "Dynamic application probe",
    editor: tree,
    default_input: None,
    initial_size: (480, 400),
    initialize: () => None,
    view: () => {
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
          kind: Input(single_line=model.invalid == 5),
        })
      }
      if model.invalid == 4 && controls.length() > 1 {
        controls.push(controls[1])
      }
      controls
    },
    activate: reference => {
      if model.invalid == 9 {
        return (model.operations.application().activate)(reference)
      }
      if reference == model.add {
        model.change(0)
        ignore(@semantics.focus(tree, model.inputs[model.inputs.length() - 1]))
      }
      None
    },
    resize: (_, _) => true,
    stop: () => {
      ignore(@semantics.dispose(tree))
      (model.operations.application().stop)()
    },
    can_close: () => true,
    close_requested: () => (),
    close_ready: () => false,
    input_error: _ => (),
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
