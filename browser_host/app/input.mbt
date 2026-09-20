///|
let input_session : Ref[@input_binding.Session?] = Ref(None)

///|
let input_start_error : Ref[Int] = Ref(0)

///|
#export_name("inputs_error")
pub fn inputs_error() -> Int {
  input_start_error.val +
  input_session.val.map(session => session.error()).unwrap_or(0)
}

///|
#export_name("inputs_composing")
pub fn inputs_composing() -> Int {
  if input_session.val.map(session => session.composing()).unwrap_or(false) {
    1
  } else {
    0
  }
}

///|
#export_name("inputs_stop")
pub fn inputs_stop() -> Unit {
  if input_session.val is Some(session) {
    session.stop()
  }
  input_session.val = None
  @app.editor_composition_end()
  @app.query_composition_end()
}

///|
fn input_binding(
  element : @input_binding.Element,
  query : Bool,
) -> @input_binding.Binding {
  {
    element,
    scroll: value => {
      if query {
        @app.query_scroll(value)
      } else {
        @app.editor_scroll(value)
      }
    },
    focus: () => ignore(@app.view_focus(if query { 6 } else { 0 })),
    begin_composition: () => {
      if query {
        @app.query_composition_start()
      } else {
        @app.editor_composition_start()
      }
    },
    end_composition: () => {
      if query {
        @app.query_composition_end()
      } else {
        @app.editor_composition_end()
      }
    },
    preedit: value => ignore(@app.input_preedit(query, value)),
    preview: (value, cursor) => @app.input_dom_preview(query, value, cursor),
    commit: (value, start, end) => @app.input_commit(query, value, start, end),
  }
}

///|
#export_name("inputs_start")
pub fn inputs_start() -> Unit {
  inputs_stop()
  input_start_error.val = 0
  guard @input_binding.textarea("text-input") is Some(editor) else {
    input_start_error.val = 1
    return
  }
  guard @input_binding.input("rpc-user") is Some(query) else {
    input_start_error.val = 1
    return
  }
  input_session.val = Some(
    @input_binding.start(
      [
        input_binding(@input_binding.Multiline(editor), false),
        input_binding(@input_binding.SingleLine(query), true),
      ],
      () => host_notify("metonic-input"),
    ),
  )
}
