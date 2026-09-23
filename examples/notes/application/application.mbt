///|
pub fn Model::application(self : Model) -> @app.Application {
  {
    title: "Metonic Notes",
    editor: self.editor,
    default_input: Some(self.note),
    initial_size: self.size(),
    viewport: None,
    connect_tasks: _ => (),
    initialize: () => None,
    view: () => {
      let elements = self.elements()
      let controls : Array[@app.Control] = [
        {
          element: elements[0],
          kind: @app.Input(single_line=false),
          clip: None,
        },
        { element: elements[1], kind: @app.Button, clip: None, },
      ]
      if self.input_error is Some(error) {
        controls.push({
          element: {
            bounds: {
              x: 16,
              y: 176,
              width: (self.width - 32).max(32).min(1024),
              height: 32,
            },
            text: error,
            reference: None,
            focused: false,
          },
          kind: @app.Text,
          clip: None,
        })
      }
      controls
    },
    activate: reference => {
      ignore(self.activate(reference))
      None
    },
    resize: (width, height) => self.resize(width, height),
    stop: () => self.stop(),
    can_close: () => true,
    close_requested: () => (),
    close_ready: () => false,
    input_error: message => self.input_error = message,
    edited: _ => None,
    dispose: () => (),
  }
}
