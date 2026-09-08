///|
let rendered_editor : Ref[
  (
    String,
    Bytes,
    Int,
    Bool,
    Int,
    Int,
    Bool,
    Int,
    Bool,
    Bool,
    Int,
    String,
    Bool,
    (Int, Int),
    Int?,
  )?,
] = Ref(None)

///|
let view_layers : Ref[Array[@view_renderer.Layer]] = Ref([])

///|
#export_name("editor_render")
pub fn editor_render(viewport_width : Int) -> Int {
  let engine = match bridge.engine {
    Some(engine) => engine
    None => return 0
  }
  ignore(
    @scene.resize(
      application.val.scene,
      viewport_width,
      @scene.field(application.val.scene, 7),
    ),
  )
  let view = application.val.view(
    query_preview=query_preview.val.unwrap_or(application.val.query()),
  )
  let text = editor_display()
  let start = editor_field(1)
  let end = editor_field(2)
  let key = (
    text,
    application.val.result_utf8,
    view.editor.bounds.width,
    view.request.focused,
    start,
    end,
    view.editor.focused,
    application.val.task_field(0),
    view.start.focused,
    view.cancel.focused,
    @scene.field(application.val.scene, 7),
    view.query.text,
    view.query.focused,
    view.query_selection,
    view.query_caret,
  )
  if rendered_editor.val == Some(key) {
    return 2
  }
  let layers = @view_renderer.render(
    engine,
    view,
    text,
    selection=(start, end),
    caret=if view.editor.focused && start == end { Some(end) } else { None },
  )
  view_layers.val = layers
  let editor = layers[0].pixels
  let status = if view.result.text != "" {
    let source = layers[2].pixels
    Bytes::makei(view.editor.bounds.width * view.result.bounds.height * 4, i => {
      let x = i / 4 % view.editor.bounds.width
      let y = i / 4 / view.editor.bounds.width
      if x < view.result.bounds.width {
        source[(y * view.result.bounds.width + x) * 4 + i % 4]
      } else {
        b'\x00'
      }
    })
  } else {
    b""
  }
  bridge.output = Some(
    Bytes::makei(editor.length() + status.length(), i => {
      if i < editor.length() {
        editor[i]
      } else {
        status[i - editor.length()]
      }
    }),
  )
  bridge.output_width = view.editor.bounds.width
  rendered_editor.val = Some(key)
  1
}

///|
#export_name("text_height")
pub fn text_height() -> Int {
  match bridge.output {
    Some(bytes) if bridge.output_width > 0 =>
      bytes.length() / (bridge.output_width * 4)
    _ => 0
  }
}

///|
#export_name("view_layer_count")
pub fn view_layer_count() -> Int {
  view_layers.val.length()
}

///|
#export_name("view_layer_field")
pub fn view_layer_field(layer : Int, field : Int) -> Int {
  if layer < 0 || layer >= view_layers.val.length() {
    return -1
  }
  let box = view_layers.val[layer].bounds
  match field {
    0 => box.x
    1 => box.y
    2 => box.width
    3 => box.height
    _ => -1
  }
}

///|
#export_name("view_layer_pixel")
pub fn view_layer_pixel(layer : Int, index : Int) -> Int {
  if layer < 0 || layer >= view_layers.val.length() {
    return -1
  }
  let bytes = view_layers.val[layer].pixels
  if index < 0 || index >= bytes.length() / 4 {
    return -1
  }
  bytes[index * 4].to_int() |
  (bytes[index * 4 + 1].to_int() << 8) |
  (bytes[index * 4 + 2].to_int() << 16) |
  (bytes[index * 4 + 3].to_int() << 24)
}

///|
#export_name("view_field")
pub fn view_field(element : Int, field : Int) -> Int {
  if @semantics.snapshot(application.val.editor).length() < 3 {
    return -1
  }
  let view = application.val.view()
  let item = match element {
    0 => view.editor
    1 => view.request
    2 => view.result
    3 => view.start
    4 => view.cancel
    5 => view.task_status
    6 => view.query
    _ => return -1
  }
  match field {
    0 => item.bounds.x
    1 => item.bounds.y
    2 => item.bounds.width
    3 => item.bounds.height
    4 => item.text.length()
    _ => -1
  }
}

///|
#export_name("view_label_unit")
pub fn view_label_unit(index : Int) -> Int {
  let text = application.val.view().request.text
  if index < 0 || index >= text.length() {
    -1
  } else {
    text[index].to_int()
  }
}

///|
#export_name("view_focus")
pub fn view_focus(element : Int) -> Int {
  let model = application.val
  let nodes = @semantics.snapshot(model.editor)
  if nodes.length() < 3 {
    return 0
  }
  let node = match element {
    0 => nodes[1]
    1 => nodes[2]
    2 => nodes[0]
    3 => nodes[3]
    4 => nodes[4]
    6 => nodes[5]
    _ => return 0
  }
  if @semantics.focus(model.editor, node.reference) == "" {
    1
  } else {
    0
  }
}
