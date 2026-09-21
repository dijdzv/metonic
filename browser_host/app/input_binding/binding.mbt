///|
pub fn window() -> @input_dom.Window {
  input_window()
}

///|
pub(all) enum Element {
  Multiline(@input_dom.HTMLTextAreaElement)
  SingleLine(@input_dom.HTMLInputElement)
}

///|
pub fn Element::set_enabled(self : Element, enabled : Bool) -> Unit {
  match self {
    Multiline(value) => value.set_disabled(!enabled)
    SingleLine(value) => value.set_disabled(!enabled)
  }
}

///|
pub fn Element::capture_scroll(self : Element) -> (Int, Bool) {
  match self {
    SingleLine(value) => (input_scroll(value), false)
    Multiline(value) => {
      let offset = editor_scroll(value)
      let limit = editor_scroll_limit(value)
      let caret_at_end = self.active() &&
        (match self.selection() {
          Some((start, end, _)) => start == end && end == self.value().length()
          None => false
        })
      (offset, if limit > 0 { offset + 1 >= limit } else { caret_at_end })
    }
  }
}

///|
pub fn Element::restore_scroll(self : Element, state : (Int, Bool)) -> Int {
  match self {
    SingleLine(value) => input_restore_scroll(value, state.0)
    Multiline(value) => editor_restore_scroll(value, state.0, state.1)
  }
}

///|
pub(all) struct Binding {
  element : Element
  scroll : (Int) -> Unit
  focus : () -> Unit
  begin_composition : () -> Int
  end_composition : () -> Unit
  preedit : (String) -> Unit
  preview : (String, Int) -> Int
  commit : (String, Int, Int) -> Int
}

///|
priv struct InputState {
  binding : Binding
  mut composing : Bool
  mut stopped : Bool
  mut preedit : String
  mut frame : UInt?
}

///|
pub struct Session {
  priv inputs : Array[InputState]
  priv listeners : Array[
    (@input_dom.EventTarget, String, @input_dom.EventListener),
  ]
  priv notify : () -> Unit
  priv mut error : Int
  priv mut stopped : Bool
}

///|
pub fn Session::error(self : Session) -> Int {
  self.error
}

///|
pub fn Session::composing(self : Session) -> Bool {
  self.inputs.any(state => state.composing && !state.stopped)
}

///|
fn Session::notify_result(self : Session, result : Int) -> Unit {
  if result != 1 {
    self.error = 1
  }
  (self.notify)()
}

///|
fn Session::sync(self : Session, state : InputState) -> Unit {
  if state.stopped {
    return
  }
  let binding = state.binding
  let element = binding.element
  (binding.scroll)(
    match element {
      SingleLine(value) => input_scroll(value)
      Multiline(value) => editor_scroll(value)
    },
  )
  guard element.selection() is Some((start, end, backward)) else {
    self.notify_result(0)
    return
  }
  if state.composing {
    (binding.preedit)(state.preedit)
    if (binding.preview)(element.value(), if backward { start } else { end }) ==
      1 {
      self.notify_result(1)
    }
  } else {
    self.notify_result((binding.commit)(element.value(), start, end))
  }
}

///|
fn Session::listen(
  self : Session,
  target : @input_dom.EventTarget,
  name : String,
  callback : (@input_dom.Event) -> Unit,
) -> Unit {
  let listener = input_add_listener(target, name, callback)
  self.listeners.push((target, name, listener))
}

///|
fn Session::bind(self : Session, state : InputState) -> Unit {
  let target = state.binding.element.target()
  let on_input = fn(event : @input_dom.Event) {
    if state.stopped || (!state.composing && input_event_composing(event)) {
      return
    }
    self.sync(state)
  }
  self.listen(target, "input", on_input)
  self.listen(target, "select", on_input)
  self.listen(target, "selectionchange", on_input)
  self.listen(target, "scroll", _ => self.sync(state))
  self.listen(target, "focus", _ => {
    if state.stopped {
      return
    }
    (state.binding.focus)()
    self.sync(state)
  })
  self.listen(target, "compositionstart", _ => {
    if state.stopped {
      return
    }
    self.sync(state)
    if state.stopped || self.error != 0 {
      return
    }
    state.composing = (state.binding.begin_composition)() == 1
  })
  self.listen(target, "compositionupdate", event => {
    if state.stopped || !state.composing {
      return
    }
    guard input_event_data(event) is Some(data) else { return }
    state.preedit = data
    // Chromium may update DOM text after compositionupdate without an input event.
    if state.frame is None {
      state.frame = Some(
        input_request_frame(_ => {
          state.frame = None
          if state.composing && !state.stopped {
            self.sync(state)
          }
        }),
      )
    }
  })
  self.listen(target, "compositionend", _ => {
    if state.stopped || !state.composing {
      return
    }
    state.composing = false
    if state.frame is Some(frame) {
      input_cancel_frame(frame)
      state.frame = None
    }
    state.preedit = ""
    (state.binding.end_composition)()
    self.sync(state)
  })
}

///|
pub fn Session::stop(self : Session) -> Unit {
  if self.stopped {
    return
  }
  self.stopped = true
  for state in self.inputs {
    state.stopped = true
    state.composing = false
    if state.frame is Some(frame) {
      input_cancel_frame(frame)
      state.frame = None
    }
  }
  for (target, name, callback) in self.listeners {
    input_remove_listener(target, name, callback)
  }
  self.listeners.clear()
  for state in self.inputs {
    (state.binding.end_composition)()
  }
  self.inputs.clear()
}

///|
pub fn start(bindings : Array[Binding], notify : () -> Unit) -> Session {
  let session = Session::{
    inputs: [],
    listeners: [],
    notify,
    error: 0,
    stopped: false,
  }
  for binding in bindings {
    let state = InputState::{
      binding,
      composing: false,
      stopped: false,
      preedit: "",
      frame: None,
    }
    session.inputs.push(state)
    session.bind(state)
  }
  session.listen(input_document_target(), "selectionchange", _ => {
    for state in session.inputs {
      if state.binding.element.active() {
        session.sync(state)
      }
    }
  })
  for state in session.inputs {
    session.sync(state)
  }
  session
}
