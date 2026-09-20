///|
let model : @note_model.Model = @note_model.create()

///|
let gpu : @gpu_renderer.Session = @gpu_renderer.create()

///|
let font : @font_loader.Loader = @font_loader.create(
  "./NotoSansJP.ttf", "c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f",
).unwrap()

///|
let engine : Ref[@raster.Engine?] = Ref(None)

///|
let inputs : Ref[@input_binding.Session?] = Ref(None)

///|
let layers : Ref[Array[@renderer.Layer]] = Ref([])

///|
let preview : Ref[(String, Int)?] = Ref(None)

///|
let composing : Ref[Bool] = Ref(false)

///|
let scroll : Ref[Int] = Ref(0)

///|
let stopped : Ref[Bool] = Ref(false)

///|
#export_name("load_font")
pub fn load_font() -> @font_loader.FontPromise {
  font.fetch()
}

///|
#export_name("install_font")
pub fn install_font(buffer : @dom.ArrayBuffer) -> Int {
  if stopped.val {
    return 0
  }
  guard buffer.to_bytes() is Some(bytes) else { return 0 }
  engine.val = @raster.create(bytes)
  if engine.val is Some(_) {
    1
  } else {
    0
  }
}

///|
#export_name("start")
pub fn start(device : @dom.GPUDevice, format : String) -> Int {
  if stopped.val || inputs.val is Some(_) {
    return 0
  }
  guard @input_binding.textarea("note") is Some(element) else { return 0 }
  if gpu.text_gpu_init(device, format) != 1 {
    return 0
  }
  element.set_value(@semantics.node(model.editor, model.note).unwrap().value)
  inputs.val = Some(
    @input_binding.start(
      [
        {
          element: @input_binding.Multiline(element),
          scroll: value => scroll.val = value.max(0),
          focus: () => ignore(@semantics.focus(model.editor, model.note)),
          begin_composition: () => {
            composing.val = true
            1
          },
          end_composition: () => {
            composing.val = false
            preview.val = None
          },
          // The DOM preview is authoritative; raw preedit data alone omits replacement context.
          preedit: _ => (),
          preview: (value, cursor) => {
            if value.length() > 1024 ||
              @text_position.utf16_to_scalar(value, cursor) is None {
              return 0
            }
            preview.val = Some((value, cursor))
            1
          },
          commit: (value, start, end) => {
            if stopped.val ||
              value.length() > 1024 ||
              start > end ||
              @text_position.utf16_to_scalar(value, start) is None ||
              @text_position.utf16_to_scalar(value, end) is None {
              return 0
            }
            if @semantics.set_text(model.editor, model.note, value) != "" {
              return 0
            }
            if @semantics.set_selection(model.editor, model.note, start, end) !=
              "" {
              return 0
            }
            1
          },
        },
      ],
      notify,
    ),
  )
  1
}

///|
#export_name("resize")
pub fn resize(width : Int, height : Int) -> Int {
  if stopped.val || width < 1 || width > 2048 || height < 1 || height > 2048 {
    return 0
  }
  ignore(model.resize(width, height))
  let view = model.elements()
  @dom_view.place(@dom_view.element("canvas"), [
    {
      element: @dom_view.element("note"),
      bounds: view[0].bounds,
      class_name: Some("gpu-input"),
    },
    {
      element: @dom_view.element("clear"),
      bounds: view[1].bounds,
      class_name: Some("gpu-button"),
    },
  ])
  1
}

///|
#export_name("render")
pub fn render() -> Int {
  if stopped.val {
    return 0
  }
  guard engine.val is Some(engine) else { return 0 }
  let view = model.elements()
  let node = @semantics.node(model.editor, model.note).unwrap()
  let (text, cursor) = preview.val.unwrap_or((node.value, node.selection_end))
  let input = { ..view[0], text, }
  let selection = if composing.val {
    (cursor, cursor)
  } else {
    (node.selection_start, node.selection_end)
  }
  let caret = if node.focused && (composing.val || selection.0 == selection.1) {
    Some(cursor)
  } else {
    None
  }
  match
    @renderer.render(engine, [
      @renderer.item(input, selection~, caret~, vertical_scroll=scroll.val),
      @renderer.item(view[1], surface=@renderer.Control),
    ]) {
    Ok(rendered) => {
      layers.val = rendered
      1
    }
    Err(_) => 0
  }
}

///|
#export_name("clear")
pub fn clear() -> Int {
  if stopped.val || composing.val || !model.activate(model.clear) {
    return 0
  }
  @input_binding.textarea("note").unwrap().set_value("")
  ignore(@semantics.focus(model.editor, model.clear))
  preview.val = None
  notify()
  1
}

///|
#export_name("layer_count")
pub fn layer_count() -> Int {
  layers.val.length()
}

///|
#export_name("layer_field")
pub fn layer_field(index : Int, field : Int) -> Int {
  if index < 0 || index >= layers.val.length() {
    return -1
  }
  let bounds = layers.val[index].bounds
  match field {
    0 => bounds.x
    1 => bounds.y
    2 => bounds.width
    3 => bounds.height
    _ => -1
  }
}

///|
#cfg(target="js")
#export_name("layer_bytes")
pub fn layer_bytes(index : Int) -> Bytes {
  layers.val[index].pixels
}

///|
#cfg(target="wasm-gc")
#export_name("layer_bytes")
pub fn layer_bytes(index : Int) -> String {
  layers.val[index].pixels.to_unchecked_string()
}

///|
#export_name("upload_begin")
pub fn upload_begin() -> Unit {
  gpu.text_gpu_abort()
}

///|
#export_name("upload_layer")
pub fn upload_layer(index : Int, pixels : @dom.ArrayBufferView) -> Int {
  if stopped.val || index < 0 || index >= layers.val.length() {
    return 0
  }
  let bounds = layers.val[index].bounds
  gpu.text_gpu_add(index, bounds.width, bounds.height, pixels)
}

///|
#export_name("upload_commit")
pub fn upload_commit() -> Int {
  if stopped.val {
    0
  } else {
    gpu.text_gpu_commit(layers.val.length())
  }
}

///|
#export_name("frame_begin")
pub fn frame_begin(context : @dom.GPUCanvasContext) -> Int {
  if stopped.val {
    0
  } else {
    gpu.gpu_frame_begin(context)
  }
}

///|
#export_name("frame_text")
pub fn frame_text(index : Int, data : @dom.ArrayBufferView) -> Int {
  gpu.gpu_frame_text(index, data)
}

///|
#export_name("frame_submit")
pub fn frame_submit() -> Int {
  gpu.gpu_frame_submit()
}

///|
#export_name("frame_abort")
pub fn frame_abort() -> Unit {
  gpu.gpu_frame_abort()
}

///|
#export_name("stop")
pub fn stop() -> Unit {
  if stopped.val {
    return
  }
  stopped.val = true
  font.cancel()
  if inputs.val is Some(session) {
    session.stop()
  }
  inputs.val = None
  gpu.gpu_frame_abort()
  gpu.text_gpu_dispose()
  layers.val = []
  engine.val = None
  model.stop()
}
