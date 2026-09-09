///|
priv enum InputElement {
  Editor(@dom.HTMLTextAreaElement)
  Query(@dom.HTMLInputElement)
}

///|
fn InputElement::target(self : InputElement) -> &@dom.TEventTarget {
  match self {
    Editor(value) => (value : &@dom.TEventTarget)
    Query(value) => (value : &@dom.TEventTarget)
  }
}

///|
fn InputElement::value(self : InputElement) -> String {
  match self {
    Editor(value) => value.value()
    Query(value) => value.value()
  }
}

///|
fn InputElement::selection(self : InputElement) -> (Int, Int, Bool) {
  match self {
    Editor(value) =>
      (
        value.selection_start().reinterpret_as_int(),
        value.selection_end().reinterpret_as_int(),
        value.selection_direction() == "backward",
      )
    Query(value) =>
      (
        value.selection_start().reinterpret_as_int(),
        value.selection_end().reinterpret_as_int(),
        value.selection_direction() == "backward",
      )
  }
}

///|
fn InputElement::active(self : InputElement) -> Bool {
  let active = @dom.document().active_element()
  match self {
    Editor(value) => active.is_same_node(value)
    Query(value) => active.is_same_node(value)
  }
}

///|
priv struct InputState {
  element : InputElement
  query : Bool
  mut composing : Bool
  mut stopped : Bool
}

///|
let inputs : Array[InputState] = []

///|
let listeners : Array[(&@dom.TEventTarget, String, (@dom.Event) -> Unit)] = []

///|
let input_error : Ref[Int] = Ref(0)

///|
fn notify_input(result : Int) -> Unit {
  if result != 1 {
    input_error.val = 1
  }
  ignore(@dom.document().dispatch_event(@dom.Event::new("metonic-input")))
}

///|
fn InputState::sync(self : InputState) -> Unit {
  if self.stopped {
    return
  }
  let (start, end, backward) = self.element.selection()
  if self.composing {
    if @app.input_cursor(
        self.query,
        self.element.value(),
        if backward {
          start
        } else {
          end
        },
      ) ==
      1 {
      notify_input(1)
    }
  } else {
    notify_input(
      @app.input_commit(self.query, self.element.value(), start, end),
    )
  }
}

///|
fn listen(
  target : &@dom.TEventTarget,
  name : String,
  callback : (@dom.Event) -> Unit,
) -> Unit {
  target.add_event_listener(name, callback)
  listeners.push((target, name, callback))
}

///|
fn bind_input(state : InputState) -> Unit {
  let target = state.element.target()
  let on_input = fn(event : @dom.Event) {
    if state.stopped {
      return
    }
    if !state.composing {
      let event : @dom.InputEvent? = event.try_into()
      if event is Some(event) && event.is_composing() {
        return
      }
    }
    state.sync()
  }
  listen(target, "input", on_input)
  listen(target, "select", on_input)
  listen(target, "selectionchange", on_input)
  listen(target, "focus", fn(_) {
    if state.stopped {
      return
    }
    ignore(@app.view_focus(if state.query { 6 } else { 0 }))
    state.sync()
  })
  listen(target, "compositionstart", fn(_) {
    if state.stopped {
      return
    }
    state.sync()
    if state.stopped || input_error.val != 0 {
      return
    }
    state.composing = (if state.query {
        @app.query_composition_start()
      } else {
        @app.editor_composition_start()
      }) ==
      1
  })
  listen(target, "compositionupdate", fn(event) {
    if state.stopped || !state.composing {
      return
    }
    let event : @dom.CompositionEvent = event.unsafe_into()
    if @app.input_preedit(state.query, event.data()) == 1 {
      notify_input(1)
    }
  })
  listen(target, "compositionend", fn(_) {
    if state.stopped || !state.composing {
      return
    }
    state.composing = false
    if state.query {
      @app.query_composition_end()
    } else {
      @app.editor_composition_end()
    }
    state.sync()
  })
}

///|
#export_name("inputs_error")
pub fn inputs_error() -> Int {
  input_error.val
}

///|
#export_name("inputs_composing")
pub fn inputs_composing() -> Int {
  if inputs.any(state => state.composing && !state.stopped) {
    1
  } else {
    0
  }
}

///|
#export_name("inputs_stop")
pub fn inputs_stop() -> Unit {
  for state in inputs {
    state.stopped = true
    state.composing = false
  }
  for entry in listeners {
    let (target, name, callback) = entry
    target.remove_event_listener(name, callback)
  }
  listeners.clear()
  inputs.clear()
  @app.editor_composition_end()
  @app.query_composition_end()
}

///|
#export_name("inputs_start")
pub fn inputs_start() -> Unit {
  inputs_stop()
  input_error.val = 0
  let editor : @dom.HTMLTextAreaElement = @dom.document()
    .get_element_by_id("text-input")
    .unsafe_into()
  let query : @dom.HTMLInputElement = @dom.document()
    .get_element_by_id("rpc-user")
    .unsafe_into()
  inputs.push({
    element: Editor(editor),
    query: false,
    composing: false,
    stopped: false,
  })
  inputs.push({
    element: Query(query),
    query: true,
    composing: false,
    stopped: false,
  })
  for state in inputs {
    bind_input(state)
  }
  listen(@dom.document(), "selectionchange", fn(_) {
    for state in inputs {
      if state.element.active() {
        state.sync()
      }
    }
  })
  for state in inputs {
    state.sync()
  }
}
