///|
pub fn from_application(app : @portable.Application) -> Application {
  let size = Ref(app.initial_size)
  let revealed : Ref[@semantics.NodeRef?] = Ref(None)
  {
    editor: app.editor,
    default_input: app.default_input,
    connect_tasks: app.connect_tasks,
    publication_round: submit => {
      let reconciled = app.reconcile_tasks(submit)
      let published = app.publish()
      reconciled || published
    },
    synchronize_controls: composing => app.synchronize_components(composing),
    initial_size: app.initial_size,
    initialize: () => {
      (app.initialize)().map(request => { request, gate: Always, })
    },
    view: () => {
      let mut controls = (app.view)()
      let nodes = @semantics.snapshot(app.editor)
      let focused = nodes
        .iter()
        .find_first(node => node.focused && node.enabled)
        .map(node => node.reference)
      if focused != revealed.val {
        revealed.val = focused
        if focused is Some(reference) && app.viewport is Some(viewport) {
          if (viewport.reveal)(reference) {
            controls = (app.view)()
          }
        }
      }
      let inputs : Array[@view_presentation.Input] = []
      for control in controls {
        if control.kind is @portable.Input(single_line~) &&
          control.element.reference is Some(reference) {
          inputs.push({ reference, single_line, })
        }
      }
      let (width, height) = size.val
      let accessibility_controls : Array[@accessibility.Control] = controls.filter_map(control => {
          control.element.reference.map(reference => {
            reference,
            bounds: control
            .visible_bounds()
            .unwrap_or({ ..control.element.bounds, width: 0, height: 0, }),
            toggled: if control.kind == @portable.Checkbox {
              nodes
              .iter()
              .find_first(node => node.reference == reference)
              .map(node => node.checked)
            } else {
              None
            },
          })
        },
      )
      for node in nodes {
        if !accessibility_controls.any(control => {
            control.reference == node.reference
          }) {
          accessibility_controls.push({
            reference: node.reference,
            bounds: { x: 0, y: 0, width: 0, height: 0, },
            toggled: None,
          })
        }
      }
      {
        items: controls.map(control => {
          let surface = match control.kind {
            @portable.Button => @renderer.Control
            @portable.Checkbox => {
              let reference = control.element.reference.unwrap()
              let node = nodes
                .iter()
                .find_first(node => node.reference == reference)
                .unwrap()
              @renderer.Checkbox(
                checked=node.checked,
                enabled=node.enabled,
                invalid=node.invalid,
              )
            }
            @portable.ListItem => {
              let reference = control.element.reference.unwrap()
              let node = nodes
                .iter()
                .find_first(node => node.reference == reference)
                .unwrap()
              @renderer.ListItem(selected=node.selected, enabled=node.enabled)
            }
            _ => @renderer.Text
          }
          @renderer.item(control.element, surface~, clip=control.clip)
        }),
        inputs,
        rectangle: None,
        accessibility: {
          title: app.title,
          width,
          height,
          controls: accessibility_controls,
          statuses: [],
          text_owner: app.default_input.filter(reference => {
            inputs.any(input => input.reference == reference)
          }),
          composing: false,
          text_scroll: 0,
        },
      }
    },
    focus_order: () => {
      (app.view)().filter_map(control => {
        if control.kind == @portable.Text || control.kind == @portable.List {
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
    edited: edit => {
      (app.edited)(edit).map(request => { request, gate: Always, })
    },
    shortcut: (_, _, _) => None,
    navigation_blocked: () => false,
    navigate_unhandled: (_, dy) => {
      guard app.components is Some(root) else { return false }
      guard @semantics.snapshot(app.editor).iter().find_first(node => node.focused)
        is Some(node) else {
        return false
      }
      let direction = if dy <= -1000000 {
        @component.First
      } else if dy >= 1000000 {
        @component.Last
      } else if dy < 0 {
        @component.Previous
      } else {
        @component.Next
      }
      root.navigate_list(node.reference, direction) is Some(_)
    },
    pointer_unhandled: (_, _) => false,
    scroll_unhandled: (x, y, delta) => {
      app.viewport
      .map(viewport => (viewport.scroll)(x, y, delta))
      .unwrap_or(false)
    },
    resize: (width, height) => {
      let changed = (app.resize)(width, height)
      if changed {
        size.val = (width, height)
        revealed.val = None
      }
      changed
    },
    stop: app.stop,
    can_close: app.can_close,
    close_requested: app.close_requested,
    close_ready: app.close_ready,
    input_error: app.input_error,
    dispose: app.dispose,
  }
}
