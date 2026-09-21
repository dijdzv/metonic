///|
async test "application item order and retained input layout are independent" {
  let font = @fs.read_file(
    @env.get_env_var("METONIC_RENDER_TEST_FONT").unwrap(),
  ).binary()
  let engine = @raster.create(font).unwrap()
  let reference = @raster.create(font).unwrap()
  let title : @view.Element = {
    bounds: { x: 40, y: 12, width: 120, height: 32, },
    text: "Notes",
    reference: None,
    focused: false,
  }
  let input : @view.Element = {
    bounds: { x: 40, y: 52, width: 200, height: 64, },
    text: "日本 ABC\nsecond line",
    reference: None,
    focused: true,
  }
  let button : @view.Element = {
    bounds: { x: 80, y: 120, width: 96, height: 40, },
    text: "Save",
    reference: None,
    focused: false,
  }
  let items = [
    @renderer.item(title),
    @renderer.item(input, selection=(0, 2)),
    @renderer.item(button, surface=Control),
  ]
  let layers = @renderer.render(engine, items, retain_layout=1).unwrap()
  assert_eq(layers.length(), 3)
  assert_eq(layers[0].bounds, title.bounds)
  assert_eq(layers[1].bounds, input.bounds)
  assert_eq(layers[2].bounds, button.bounds)
  assert_eq(
    layers[1].pixels,
    @raster.render(reference, input.text, 200, 64, selection=(0, 2)),
  )
  assert_eq(
    @raster.hit_caret(engine, 40, 12),
    @raster.hit_caret(reference, 40, 12),
  )
  assert_true(@raster.text_runs(engine, input.text) is Some(_))
  assert_true(@raster.text_runs(engine, button.text) is None)
  let reordered_layout = @renderer.render(engine, items, retain_layout=0).unwrap()
  assert_eq(reordered_layout[1].pixels, layers[1].pixels)
  assert_true(@raster.text_runs(engine, title.text) is Some(_))
  assert_true(
    @renderer.render(engine, items, retain_layout=3)
    is Err("invalid_retained_item"),
  )
  assert_true(@raster.text_runs(engine, title.text) is Some(_))
  assert_true(
    @renderer.render(engine, [
      @renderer.item({ ..title, bounds: { ..title.bounds, width: 0, }, }),
    ])
    is Err("invalid_item_bounds"),
  )
  let tall = {
    ..input,
    bounds: { ..input.bounds, height: 300, },
    text: "one\ntwo\nthree\nfour\nfive\nsix",
  }
  let tall_layer = @renderer.render(engine, [@renderer.item(tall)]).unwrap()[0]
  assert_eq(tall_layer.pixels.length(), 200 * 300 * 4)
  assert_true(@raster.hit_caret(engine, 0, 160).unwrap().0 >= 24)
  assert_eq(@raster.render(engine, "", 1, 1024).length(), 4096)
  assert_eq(@raster.render(engine, "", 1, 1025).length(), 0)
  assert_true(
    @renderer.render(engine, [
      @renderer.item({ ..tall, bounds: { ..tall.bounds, height: 1025, }, }),
    ])
    is Err("invalid_item_bounds"),
  )
}
