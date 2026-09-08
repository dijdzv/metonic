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
  query : Element
  query_label : Element
  query_selection : (Int, Int)
  query_caret : Int?
  request : Element
  result : Element
  task_status : Element
  start : Element
  cancel : Element
}

///|
pub fn Model::view(self : Model, query_preview? : String) -> View {
  let nodes = @semantics.snapshot(self.editor)
  let width = (@scene.field(self.scene, 6) - 16).max(1).min(640)
  let compact = @scene.field(self.scene, 7) < 352 && width >= 384
  let start_width = if compact {
    (width - 120).min(272)
  } else {
    width.min(272)
  }
  let editor = nodes[1]
  let request = nodes[2]
  let query = nodes[5]
  {
    query_selection: (query.selection_start, query.selection_end),
    query_caret: if query.focused &&
      query.selection_start == query.selection_end {
      Some(@semantics.caret(query))
    } else {
      None
    },
    query_label: {
      bounds: { x: 192, y: 104, width: 32, height: 32, },
      text: "ID",
      reference: None,
      focused: false,
    },
    query: {
      bounds: { x: 224, y: 104, width: (width - 216).max(1), height: 32, },
      text: query_preview.unwrap_or(query.value),
      reference: Some(query.reference),
      focused: query.focused,
    },
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
      bounds: { x: 8, y: 104, width: width.min(176), height: 32, },
      text: self.result.trim().to_owned(),
      reference: None,
      focused: false,
    },
    task_status: {
      bounds: {
        x: 8,
        y: if compact {
          184
        } else {
          320
        },
        width: if compact {
          176
        } else {
          width
        },
        height: 32,
      },
      text: match self.task_field(0) {
        0 => "Idle"
        1 => "Working..."
        2 => "Completed"
        3 => "Failed"
        4 => "Canceled"
        _ => "Stopped"
      },
      reference: None,
      focused: false,
    },
    start: {
      bounds: {
        x: 8,
        y: if compact {
          216
        } else {
          224
        },
        width: start_width,
        height: 40,
      },
      text: nodes[3].name,
      reference: Some(nodes[3].reference),
      focused: nodes[3].focused,
    },
    cancel: {
      bounds: {
        x: if compact {
          16 + start_width
        } else {
          8
        },
        y: if compact {
          216
        } else {
          272
        },
        width: if compact {
          (width - start_width - 8).min(176)
        } else {
          width.min(176)
        },
        height: 40,
      },
      text: nodes[4].name,
      reference: Some(nodes[4].reference),
      focused: nodes[4].focused,
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
pub fn Model::control_focused(self : Model) -> Bool {
  let view = self.view()
  view.request.focused || view.start.focused || view.cancel.focused
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
    element(self.start, "button", Json::string("start_update")),
    element(self.cancel, "button", Json::string("cancel_update")),
    element(self.task_status, "status", Json::null()),
    element(self.query, "text_input", Json::null()),
  ])
}
