///|
pub fn create(model : @notes.Model) -> @host.Application {
  {
    editor: model.editor,
    default_input: model.note,
    initial_size: model.size(),
    initialize: () => (),
    view: () => {
      let elements = model.elements()
      let (width, height) = model.size()
      {
        items: [
          @renderer.item(elements[0]),
          @renderer.item(elements[1], surface=Control),
        ],
        inputs: [{ reference: model.note, single_line: false, }],
        rectangle: None,
        accessibility: {
          title: "Metonic Notes",
          width,
          height,
          controls: elements.map(element => {
            reference: element.reference.unwrap(),
            bounds: element.bounds,
            toggled: None,
          }),
          statuses: [],
          text_owner: Some(model.note),
          composing: false,
          text_scroll: 0,
        },
      }
    },
    focus_order: () => [model.note, model.clear],
    activate: reference => {
      ignore(model.activate(reference))
      None
    },
    activate_unhandled: () => false,
    shortcut: (_, _, _) => None,
    navigation_blocked: () => false,
    navigate_unhandled: (_, _) => false,
    pointer_unhandled: (_, _) => false,
    resize: (width, height) => model.resize(width, height),
    stop: () => model.stop(),
  }
}
