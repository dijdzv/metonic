///|
#export_name("create")
pub fn create() -> @host.Instance {
  let app = @model.create_collection(
    {
      load: () => @storage.load("metonic-notes.snapshot.v1"),
      save: value => @storage.save("metonic-notes.snapshot.v1", value),
    },
    () => (),
  )
  @host.create(
    app,
    [],
    root_id=Some("controls"),
    canvas_id="canvas",
    event_name="notes-refresh",
    font_url="./NotoSansJP.ttf",
    font_sha256="c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f",
  )
}
