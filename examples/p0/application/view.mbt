///|
pub struct Bounds {
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Eq, Debug)

///|
pub fn Bounds::contains(self : Bounds, x : Int, y : Int) -> Bool {
  x >= self.x &&
  x < self.x + self.width &&
  y >= self.y &&
  y < self.y + self.height
}

///|
pub struct Element {
  bounds : Bounds
  text : String
  reference : @semantics.NodeRef?
  focused : Bool
}

///|
pub struct View {
  editor : Element
  request : Element
  result : Element
}

///|
pub fn Model::view(self : Model) -> View {
  let nodes = @semantics.snapshot(self.editor)
  let width = (@scene.field(self.scene, 6) - 16).max(1).min(640)
  let editor = nodes[1]
  let request = nodes[2]
  {
    editor: {
      bounds: { x: 8, y: 8, width, height: 96, },
      text: editor.value,
      reference: Some(editor.reference),
      focused: editor.focused,
    },
    request: {
      bounds: { x: 8, y: 144, width: width.min(176), height: 40, },
      text: request.name,
      reference: Some(request.reference),
      focused: request.focused,
    },
    result: {
      bounds: { x: 8, y: 104, width, height: 32, },
      text: self.result.trim().to_owned(),
      reference: None,
      focused: false,
    },
  }
}

///|
pub fn Model::focus_request(self : Model) -> Bool {
  @semantics.focus(self.editor, self.request_button) == ""
}

///|
pub fn Model::request_focused(self : Model) -> Bool {
  for node in @semantics.snapshot(self.editor) {
    if node.reference == self.request_button {
      return node.focused
    }
  }
  false
}

///|
pub fn View::snapshot(self : View) -> Json {
  fn element(item : Element, role : String, action : Json) -> Json {
    {
      "id": match item.reference {
        Some(reference) => Json::number(reference.id.to_double())
        None => Json::null()
      },
      "role": role,
      "text": item.text,
      "focused": item.focused,
      "action": action,
      "x": item.bounds.x,
      "y": item.bounds.y,
      "width": item.bounds.width,
      "height": item.bounds.height,
    }
  }
  Json::array([
    element(self.editor, "text_input", Json::null()),
    element(self.request, "button", Json::string("load_user")),
    element(self.result, "status", Json::null()),
  ])
}
