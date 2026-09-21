///|
pub(all) struct Binding {
  reference : @semantics.NodeRef
  element_id : String
}

///|
priv struct Editor {
  reference : @semantics.NodeRef
  element : @input_binding.Element
  single_line : Bool
  mut preview : (String, Int)?
  mut composing : Bool
  mut scroll : Int
}

///|
priv struct Session {
  application : @app.Application
  bindings : Array[Binding]
  canvas_id : String
  event_name : String
  font : @font_loader.Loader
  gpu : @gpu_renderer.Session
  editors : Array[Editor]
  mut inputs : @input_binding.Session?
  mut engine : @raster.Engine?
  mut layers : Array[@renderer.Layer]
  mut stopped : Bool
  tasks : @task_driver.Driver
}

///|
fn Editor::sync(self : Editor, tree : @semantics.Tree) -> Unit {
  guard @semantics.node(tree, self.reference) is Ok(node) else { return }
  self.element.set_enabled(node.enabled)
  if self.element.value() != node.value {
    match self.element {
      Multiline(value) => value.set_value(node.value)
      SingleLine(value) => value.set_value(node.value)
    }
  }
}

///|
fn Session::notify(self : Session) -> Unit {
  if !self.stopped {
    dispatch(self.event_name)
  }
}

///|
fn Session::submit(self : Session, request : @task.Request) -> Bool {
  let accepted = self.tasks.submit(request)
  if accepted {
    // DOM callbacks run outside the async scheduler; waking a queue alone does
    // not drain runnable coroutines until the host re-enters the event loop.
    @async.run_async_main(() => ())
  }
  accepted
}

///|
fn Session::start(
  self : Session,
  device : @dom.GPUDevice,
  format : String,
) -> Int {
  if self.stopped || self.inputs is Some(_) {
    return 0
  }
  let view = (self.application.view)()
  let editors : Array[Editor] = []
  for control in view {
    if control.kind is @app.Input(single_line~) {
      guard control.element.reference is Some(reference) else { return 0 }
      guard self.bindings
        .iter()
        .find_first(binding => binding.reference == reference)
        is Some(binding) else {
        return 0
      }
      let element = if single_line {
        guard @input_binding.input(binding.element_id) is Some(value) else {
          return 0
        }
        @input_binding.SingleLine(value)
      } else {
        guard @input_binding.textarea(binding.element_id) is Some(value) else {
          return 0
        }
        @input_binding.Multiline(value)
      }
      editors.push({
        reference,
        element,
        single_line,
        preview: None,
        composing: false,
        scroll: 0,
      })
    }
  }
  if self.gpu.text_gpu_init(device, format) != 1 {
    return 0
  }
  self.editors.append(editors)
  let tree = self.application.editor
  let input_bindings = self.editors.map(editor => {
    editor.sync(tree)
    @input_binding.Binding::{
      element: editor.element,
      scroll: value => editor.scroll = value.max(0),
      focus: () => ignore(@semantics.focus(tree, editor.reference)),
      begin_composition: () => {
        editor.composing = true
        1
      },
      end_composition: () => {
        editor.composing = false
        editor.preview = None
      },
      // DOM preview includes replacement context that raw preedit text does not.
      preedit: _ => (),
      preview: (value, cursor) => {
        if self.stopped ||
          value.length() > 1024 ||
          @text_position.utf16_to_scalar(value, cursor) is None {
          return 0
        }
        editor.preview = Some((value, cursor))
        1
      },
      commit: (value, start, end) => {
        guard @semantics.node(tree, editor.reference) is Ok(node) &&
          node.enabled else {
          return 0
        }
        if self.stopped ||
          value.length() > 1024 ||
          start > end ||
          @text_position.utf16_to_scalar(value, start) is None ||
          @text_position.utf16_to_scalar(value, end) is None {
          return 0
        }
        if @semantics.set_text(tree, editor.reference, value) != "" {
          return 0
        }
        if @semantics.set_selection(tree, editor.reference, start, end) != "" {
          return 0
        }
        1
      },
    }
  })
  self.inputs = Some(@input_binding.start(input_bindings, () => self.notify()))
  if (self.application.initialize)() is Some(request) {
    ignore(self.submit(request))
  }
  1
}

///|
async fn Session::run_tasks(self : Session) -> Unit {
  defer @async.protect_from_cancel(self.application.dispose)
  defer self.stop()
  self.tasks.run(completion => {
    if !self.stopped {
      if completion.apply() is Changed {
        for editor in self.editors {
          editor.sync(self.application.editor)
        }
        self.notify()
      }
    }
  })
}

///|
fn Session::resize(self : Session, width : Int, height : Int) -> Int {
  if self.stopped || width < 1 || width > 2048 || height < 1 || height > 2048 {
    return 0
  }
  ignore((self.application.resize)(width, height))
  let placements : Array[@dom_view.Placement] = []
  for control in (self.application.view)() {
    if control.element.reference is Some(reference) &&
      self.bindings.iter().find_first(binding => binding.reference == reference)
      is Some(binding) {
      placements.push({
        element: @dom_view.element(binding.element_id),
        bounds: control.element.bounds,
        class_name: match control.kind {
          @app.Input(..) => Some("gpu-input")
          @app.Button => Some("gpu-button")
          @app.Text => None
        },
      })
    }
  }
  @dom_view.place(@dom_view.element(self.canvas_id), placements)
  1
}

///|
fn Session::render(self : Session) -> Int {
  if self.stopped {
    return 0
  }
  guard self.engine is Some(engine) else { return 0 }
  let items : Array[@renderer.Item] = []
  for control in (self.application.view)() {
    if control.kind is @app.Input(..) &&
      control.element.reference is Some(reference) {
      guard self.editors
        .iter()
        .find_first(editor => editor.reference == reference)
        is Some(editor) else {
        return 0
      }
      guard @semantics.node(self.application.editor, reference) is Ok(node) else {
        return 0
      }
      let (text, cursor) = editor.preview.unwrap_or(
        (node.value, node.selection_end),
      )
      let selection = if editor.composing {
        (cursor, cursor)
      } else {
        (node.selection_start, node.selection_end)
      }
      let caret = if node.focused &&
        (editor.composing || selection.0 == selection.1) {
        Some(cursor)
      } else {
        None
      }
      items.push(
        @renderer.item(
          { ..control.element, text, },
          selection~,
          caret~,
          single_line_scroll=if editor.single_line {
            Some(editor.scroll)
          } else {
            None
          },
          vertical_scroll=if editor.single_line { 0 } else { editor.scroll },
        ),
      )
    } else {
      items.push(
        @renderer.item(
          control.element,
          surface=if control.kind == @app.Button {
            @renderer.Control
          } else {
            @renderer.Text
          },
        ),
      )
    }
  }
  match @renderer.render(engine, items) {
    Ok(layers) => {
      self.layers = layers
      1
    }
    Err(_) => 0
  }
}

///|
fn Session::activate(self : Session, index : Int) -> Int {
  if self.stopped || self.editors.any(editor => editor.composing) {
    return 0
  }
  let view = (self.application.view)()
  if index < 0 || index >= self.bindings.length() {
    return 0
  }
  let reference = self.bindings[index].reference
  if !view.any(control => {
      control.kind == @app.Button &&
      control.element.reference == Some(reference)
    }) {
    return 0
  }
  guard @semantics.node(self.application.editor, reference) is Ok(node) else {
    return 0
  }
  if !node.enabled {
    return 0
  }
  if (self.application.activate)(reference) is Some(request) {
    if !self.submit(request) {
      return 0
    }
  }
  ignore(@semantics.focus(self.application.editor, reference))
  for editor in self.editors {
    editor.preview = None
    editor.sync(self.application.editor)
  }
  self.notify()
  1
}

///|
fn Session::stop(self : Session) -> Unit {
  if self.stopped {
    return
  }
  self.stopped = true
  self.tasks.close()
  @async.run_async_main(() => ())
  self.font.cancel()
  if self.inputs is Some(inputs) {
    inputs.stop()
  }
  self.inputs = None
  self.editors.clear()
  self.gpu.gpu_frame_abort()
  self.gpu.text_gpu_dispose()
  self.layers = []
  self.engine = None
  (self.application.stop)()
}
