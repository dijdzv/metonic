///|
priv struct PointerDrag {
  reference : @semantics.NodeRef
  anchor : Int
  text : String
  mut caret : Int
  mut x : Int
  mut y : Int
  mut next_scroll : Int64
}

///|
fn App::scroll_pointer(app : App, delta : Int) -> Unit raise {
  guard delta != 0 &&
    app.pointer_position is Some((x, y)) &&
    app.presenter is Some(presenter) else {
    return
  }
  let view = (app.host.view)()
  for index = view.items.length() - 1; index >= 0; index = index - 1 {
    let item = view.items[index]
    if !item.element.bounds.contains(x, y) {
      continue
    }
    guard item.element.reference is Some(reference) else { return }
    if presenter.scroll_input(reference, delta) {
      app.draw()
    }
    return
  }
}

///|
fn App::cancel_pointer(app : App) -> Unit {
  // Capture loss after a normal release must not erase a deferred IME click.
  if app.pointer_pressed {
    app.ime_pointer.cancel()
  }
  app.pointer_pressed = false
  app.drag = None
}

///|
fn App::move_drag(app : App, x : Int, y : Int) -> Unit raise {
  guard app.drag is Some(drag) && app.pointer_pressed else { return }
  guard app.composition is None && !app.ime_pointer.pending() else {
    app.cancel_pointer()
    return
  }
  guard @semantics.node(app.host.editor, drag.reference) is Ok(node) &&
    node.enabled &&
    node.focused &&
    node.value == drag.text &&
    node.selection_anchor == drag.anchor &&
    node.selection_start == drag.anchor.min(drag.caret) &&
    node.selection_end == drag.anchor.max(drag.caret) else {
    app.cancel_pointer()
    return
  }
  guard app.presenter is Some(presenter) else {
    app.cancel_pointer()
    return
  }
  let item = (app.host.view)().items
    .iter()
    .find_first(item => item.element.reference == Some(drag.reference))
  guard item is Some(item) else {
    app.cancel_pointer()
    return
  }
  let bounds = item.element.bounds
  drag.x = x
  drag.y = y
  drag.next_scroll = @async.now() + 50L
  // Bound each out-of-field update so one distant coordinate does not skip
  // the entire document; retained caret following advances the viewport.
  let hit_x = x.max(bounds.x - 16).min(bounds.x + bounds.width + 16)
  let hit_y = y.max(bounds.y - 32).min(bounds.y + bounds.height + 32)
  guard presenter.hit_input(drag.reference, hit_x, hit_y)
    is Some((offset, after)) else {
    return
  }
  let caret = offset.min(node.value.length())
  guard @semantics.set_selection_directed(
      app.host.editor,
      drag.reference,
      drag.anchor,
      caret,
    ) ==
    "" else {
    app.cancel_pointer()
    return
  }
  drag.caret = caret
  presenter.reveal_input(drag.reference)
  if presenter.input_width(drag.reference) is Some(width) {
    ignore(
      app.input_navigation.remember(drag.reference, caret, width, after, None),
    )
  }
  app.draw()
}

///|
fn App::scroll_drag(app : App) -> Unit raise {
  guard app.drag is Some(drag) && @async.now() >= drag.next_scroll else {
    return
  }
  let item = (app.host.view)().items
    .iter()
    .find_first(item => item.element.reference == Some(drag.reference))
  guard item is Some(item) else {
    app.cancel_pointer()
    return
  }
  if !item.element.bounds.contains(drag.x, drag.y) {
    app.move_drag(drag.x, drag.y)
  }
}

///|
fn App::apply_pointer(
  app : App,
  x : Int,
  y : Int,
  extend_selection : Bool,
) -> Unit raise {
  let view = (app.host.view)()
  for index = view.items.length() - 1; index >= 0; index = index - 1 {
    let item = view.items[index]
    if !item.element.bounds.contains(x, y) {
      continue
    }
    guard item.element.reference is Some(reference) else { continue }
    let node = match @semantics.node(app.host.editor, reference) {
      Ok(node) => node
      Err(_) => continue
    }
    if !node.enabled {
      continue
    }
    if node.role == @semantics.TextInput {
      ignore(@semantics.focus(app.host.editor, reference))
      if app.presenter is Some(presenter) {
        if presenter.hit_input(reference, x, y) is Some((offset, after)) {
          let caret = offset.min(node.value.length())
          ignore(
            @semantics.set_selection_directed(
              app.host.editor,
              reference,
              if extend_selection {
                node.selection_anchor
              } else {
                caret
              },
              caret,
            ),
          )
          if presenter.input_width(reference) is Some(width) {
            ignore(
              app.input_navigation.remember(
                reference,
                caret,
                width,
                after,
                None,
              ),
            )
          }
          if app.pointer_pressed {
            let selected = @semantics.node(app.host.editor, reference).unwrap()
            app.drag = Some({
              reference,
              anchor: selected.selection_anchor,
              text: selected.value,
              caret,
              x,
              y,
              next_scroll: @async.now() + 50L,
            })
          }
        }
      }
    } else {
      ignore(@semantics.focus(app.host.editor, reference))
      if (app.host.activate)(reference) is Some(action) {
        app.queue(ApplicationTask(action.request, action.gate))
      }
    }
    app.draw()
    return
  }
  ignore((app.host.pointer_unhandled)(x, y))
  app.draw()
}
