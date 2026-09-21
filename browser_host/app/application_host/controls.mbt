///|
priv enum ControlKey {
  Semantic(@semantics.NodeRef)
  TextPosition(Int)
} derive(Eq)

///|
priv struct OwnedControl {
  key : ControlKey
  kind : @app.Kind
  id : String
  element : @dom.HTMLElement
  remove_listener : () -> Unit
}

///|
fn control_key(control : @app.Control, index : Int) -> ControlKey {
  match control.element.reference {
    Some(reference) => Semantic(reference)
    None => TextPosition(index)
  }
}

///|
fn Session::reconcile_controls(
  self : Session,
  view : Array[@app.Control],
) -> Bool {
  guard self.managed_root is Some(root_id) else { return true }
  let keys : Array[ControlKey] = []
  for index, control in view {
    let key = control_key(control, index)
    if keys.contains(key) {
      return false
    }
    if control.kind != @app.Text {
      guard control.element.reference is Some(reference) else { return false }
      guard @semantics.node(self.application.editor, reference) is Ok(node) else {
        return false
      }
      let compatible = match control.kind {
        @app.Button => node.role == @semantics.Button
        @app.Input(..) => node.role == @semantics.TextInput
        @app.Text => true
      }
      if !compatible {
        return false
      }
    }
    if self.owned.iter().find_first(owned => owned.key == key) is Some(owned) &&
      owned.kind != control.kind {
      return false
    }
    keys.push(key)
  }
  // Removing DOM can dispatch focus/composition events synchronously. Revoke
  // the input listener before detaching, not after the browser has notified it.
  for editor in self.editors {
    if !keys.contains(Semantic(editor.reference)) {
      editor.retire()
    }
  }
  let root = match self.root_element {
    Some(root) => root
    None => {
      let root = @dom_view.element(root_id)
      if !@dom_view.claim_root(root) {
        return false
      }
      self.root_element = Some(root)
      root
    }
  }
  let retained : Array[OwnedControl] = []
  for owned in self.owned {
    if keys.contains(owned.key) {
      retained.push(owned)
    } else {
      (owned.remove_listener)()
      @dom_view.remove_control(root, owned.element)
    }
  }
  self.owned.clear()
  self.owned.append(retained)
  let ordered : Array[OwnedControl] = []
  let bindings : Array[Binding] = []
  let placements : Array[@dom_view.Placement] = []
  for index, control in view {
    let key = keys[index]
    let owned = match self.owned.iter().find_first(owned => owned.key == key) {
      Some(owned) => owned
      None => {
        let id = root_id + "-metonic-" + self.next_control.to_string()
        self.next_control += 1
        let tag = match control.kind {
          @app.Button => "button"
          @app.Input(single_line=true) => "input"
          @app.Input(single_line=false) => "textarea"
          @app.Text => "span"
        }
        let element = @dom_view.create_control(root, id, tag)
        let remove_listener = if control.kind == @app.Button &&
          control.element.reference is Some(reference) {
          @dom_view.on_click(element, () => {
            ignore(self.activate_reference(reference))
          })
        } else {
          () => ()
        }
        let created = OwnedControl::{
          key,
          kind: control.kind,
          id,
          element,
          remove_listener,
        }
        self.owned.push(created)
        created
      }
    }
    ordered.push(owned)
    @dom_view.order_control(root, owned.element)
    if control.element.reference is Some(reference) {
      bindings.push({ reference, element_id: owned.id, })
      if @semantics.node(self.application.editor, reference) is Ok(node) {
        @dom_view.label(owned.element, node.name)
      }
    }
    if control.kind == @app.Text {
      @dom_view.text(owned.element, control.element.text)
    }
    placements.push({
      element: owned.element,
      bounds: control.element.bounds,
      class_name: Some(
        match control.kind {
          @app.Button => "gpu-button"
          @app.Input(..) => "gpu-input"
          @app.Text => "gpu-text"
        },
      ),
    })
  }
  self.owned.clear()
  self.owned.append(ordered)
  self.bindings.clear()
  self.bindings.append(bindings)
  @dom_view.place(@dom_view.element(self.canvas_id), placements)
  true
}

///|
fn Session::release_controls(self : Session) -> Unit {
  guard self.root_element is Some(root) else { return }
  for owned in self.owned {
    (owned.remove_listener)()
    @dom_view.remove_control(root, owned.element)
  }
  self.owned.clear()
  self.bindings.clear()
  @dom_view.release_root(root)
  self.root_element = None
}
