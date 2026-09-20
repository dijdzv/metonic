///|
pub struct Model {
  editor : @semantics.Tree
  note : @semantics.NodeRef
  clear : @semantics.NodeRef
  priv mut width : Int
  priv mut height : Int
}

///|
pub fn create() -> Model {
  let editor = @semantics.empty(7, 9)
  let note = @semantics.add_input(
    editor, "Note", "A small independent application",
  ).unwrap()
  let clear = @semantics.add_button(editor, "Clear note").unwrap()
  ignore(@semantics.focus(editor, note))
  { editor, note, clear, width: 480, height: 240, }
}

///|
pub fn Model::size(self : Model) -> (Int, Int) {
  (self.width, self.height)
}

///|
pub fn Model::resize(self : Model, width : Int, height : Int) -> Bool {
  if width < 1 || height < 1 || width > 2048 || height > 2048 {
    return false
  }
  let changed = self.width != width || self.height != height
  self.width = width
  self.height = height
  changed
}

///|
pub fn Model::elements(self : Model) -> Array[@view.Element] {
  let note = @semantics.node(self.editor, self.note).unwrap()
  let clear = @semantics.node(self.editor, self.clear).unwrap()
  [
    {
      bounds: {
        x: 16,
        y: 16,
        width: (self.width - 32).max(32).min(1024),
        height: 96,
      },
      text: note.value,
      reference: Some(self.note),
      focused: note.focused,
    },
    {
      bounds: { x: 16, y: 128, width: 128, height: 32, },
      text: "Clear note",
      reference: Some(self.clear),
      focused: clear.focused,
    },
  ]
}

///|
pub fn Model::activate(self : Model, reference : @semantics.NodeRef) -> Bool {
  if reference != self.clear {
    return false
  }
  @semantics.set_text(self.editor, self.note, "") == ""
}

///|
pub fn Model::stop(self : Model) -> Unit {
  ignore(@semantics.dispose(self.editor))
}
