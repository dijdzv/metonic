///|
#export_name("create")
pub fn create() -> @host.Instance {
  @host.create(
    @gallery.create(),
    [],
    root_id=Some("controls"),
    canvas_id="canvas",
    event_name="metonic-notes",
    font_url="./NotoSansJP.ttf",
    font_sha256="c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f",
  )
}
