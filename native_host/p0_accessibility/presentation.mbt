///|
pub fn presentation(
  model : @application.Model,
  composing? : Bool = false,
  editor_scroll? : Int = 0,
) -> @accessibility.Presentation {
  let view = model.view()
  let nodes = @semantics.snapshot(model.editor)
  let controls : Array[@accessibility.Control] = [
    {
      reference: nodes[0].reference,
      bounds: {
        x: @scene.field(model.scene, 0),
        y: @scene.field(model.scene, 1),
        width: @scene.field(model.scene, 2),
        height: @scene.field(model.scene, 3),
      },
      toggled: Some(nodes[0].value == "on"),
    },
  ]
  for
    element in [view.editor, view.request, view.start, view.cancel, view.query] {
    controls.push({
      reference: element.reference.unwrap(),
      bounds: element.bounds,
      toggled: None,
    })
  }
  let statuses : Array[@accessibility.Status] = []
  if model.result != "" {
    statuses.push({
      id: 4294967295UL,
      text: model.result.trim().to_owned(),
      bounds: view.result.bounds,
    })
  }
  statuses.push({
    id: 4294967294UL,
    text: view.task_status.text,
    bounds: view.task_status.bounds,
  })
  {
    title: "Metonic",
    width: @scene.field(model.scene, 6),
    height: @scene.field(model.scene, 7),
    controls,
    statuses,
    text_owner: Some(nodes[1].reference),
    composing,
    text_scroll: editor_scroll,
  }
}
