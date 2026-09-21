///|
pub fn Model::application(self : Model) -> @app.Application {
  {
    title: "Metonic Notes",
    editor: self.editor,
    default_input: self.note,
    initial_size: self.size(),
    view: () => {
      let elements = self.elements()
      [
        { element: elements[0], kind: @app.Input(single_line=false), },
        { element: elements[1], kind: @app.Button, },
      ]
    },
    activate: reference => ignore(self.activate(reference)),
    resize: (width, height) => self.resize(width, height),
    stop: () => self.stop(),
  }
}
