///|
pub fn from_application(app : @portable.Application) -> Application {
  let size = Ref(app.initial_size)
  {
    editor: app.editor,
    default_input: app.default_input,
    initial_size: app.initial_size,
    initialize: () => {
      (app.initialize)().map(request => { request, gate: Always, })
    },
    view: () => {
      let controls = (app.view)()
      let inputs : Array[@view_presentation.Input] = []
      for control in controls {
        if control.kind is @portable.Input(single_line~) &&
          control.element.reference is Some(reference) {
          inputs.push({ reference, single_line, })
        }
      }
      let (width, height) = size.val
      {
        items: controls.map(control => {
          let surface = if control.kind == @portable.Button {
            @renderer.Control
          } else {
            @renderer.Text
          }
          @renderer.item(control.element, surface~)
        }),
        inputs,
        rectangle: None,
        accessibility: {
          title: app.title,
          width,
          height,
          controls: controls.filter_map(control => {
            control.element.reference.map(reference => {
              reference,
              bounds: control.element.bounds,
              toggled: None,
            })
          }),
          statuses: [],
          text_owner: Some(app.default_input),
          composing: false,
          text_scroll: 0,
        },
      }
    },
    focus_order: () => {
      (app.view)().filter_map(control => {
        if control.kind == @portable.Text {
          None
        } else {
          control.element.reference
        }
      })
    },
    activate: reference => {
      (app.activate)(reference).map(request => {
        request,
        gate: CommittedInput,
      })
    },
    activate_unhandled: () => false,
    shortcut: (_, _, _) => None,
    navigation_blocked: () => false,
    navigate_unhandled: (_, _) => false,
    pointer_unhandled: (_, _) => false,
    resize: (width, height) => {
      let changed = (app.resize)(width, height)
      if changed {
        size.val = (width, height)
      }
      changed
    },
    stop: app.stop,
    can_close: app.can_close,
    dispose: app.dispose,
  }
}
