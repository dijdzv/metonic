///|
priv enum InputElement {
  Editor(@input_dom.HTMLTextAreaElement)
  Query(@input_dom.HTMLInputElement)
}

///|
priv struct InputState {
  element : InputElement
  query : Bool
  mut composing : Bool
  mut stopped : Bool
  mut preedit : String
  mut frame : UInt?
}

///|
let inputs : Array[InputState] = []

///|
let listeners : Array[
  (@input_dom.EventTarget, String, @input_dom.EventListener),
] = []

///|
let input_error : Ref[Int] = Ref(0)

///|
fn notify_input(result : Int) -> Unit {
  if result != 1 {
    input_error.val = 1
  }
  input_notify()
}

///|
fn InputState::sync(self : InputState) -> Unit {
  if self.stopped {
    return
  }
  if self.element is Query(value) {
    @app.query_scroll(input_scroll(value))
  } else if self.element is Editor(value) {
    @app.editor_scroll(editor_scroll(value))
  }
  guard self.element.selection() is Some((start, end, backward)) else {
    notify_input(0)
    return
  }
  if self.composing {
    ignore(@app.input_preedit(self.query, self.preedit))
    if @app.input_dom_preview(
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
  target : @input_dom.EventTarget,
  name : String,
  callback : (@input_dom.Event) -> Unit,
) -> Unit {
  let listener = input_add_listener(target, name, callback)
  listeners.push((target, name, listener))
}

///|
fn bind_input(state : InputState) -> Unit {
  let target = state.element.target()
  let on_input = fn(event : @input_dom.Event) {
    if state.stopped {
      return
    }
    if !state.composing {
      if input_event_composing(event) {
        return
      }
    }
    state.sync()
  }
  listen(target, "input", on_input)
  listen(target, "select", on_input)
  listen(target, "selectionchange", on_input)
  listen(target, "scroll", fn(_) { state.sync() })
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
    guard input_event_data(event) is Some(data) else { return }
    state.preedit = data
    // Chromium updates DOM text after compositionupdate and its microtasks.
    // Existing-text composition may have no subsequent input event.
    if state.frame is None {
      state.frame = Some(
        input_request_frame(fn(_) {
          state.frame = None
          if state.composing && !state.stopped {
            state.sync()
          }
        }),
      )
    }
  })
  listen(target, "compositionend", fn(_) {
    if state.stopped || !state.composing {
      return
    }
    state.composing = false
    if state.frame is Some(frame) {
      input_cancel_frame(frame)
      state.frame = None
    }
    state.preedit = ""
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
    if state.frame is Some(frame) {
      input_cancel_frame(frame)
      state.frame = None
    }
  }
  for entry in listeners {
    let (target, name, callback) = entry
    input_remove_listener(target, name, callback)
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
  guard input_editor() is Some(editor) else {
    input_error.val = 1
    return
  }
  guard input_query() is Some(query) else {
    input_error.val = 1
    return
  }
  inputs.push({
    element: Editor(editor),
    query: false,
    composing: false,
    stopped: false,
    preedit: "",
    frame: None,
  })
  inputs.push({
    element: Query(query),
    query: true,
    composing: false,
    stopped: false,
    preedit: "",
    frame: None,
  })
  for state in inputs {
    bind_input(state)
  }
  listen(input_document_target(), "selectionchange", fn(_) {
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
