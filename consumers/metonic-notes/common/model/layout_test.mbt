///|
test "supported compact and expanded sizes keep every control inside and separate" {
  let app = create_collection(
    { load: () => Ok(None), save: _ => Ok(()), },
    () => (),
    _ => (),
  )
  for
    (width, height) in [
      (320, 360),
      (480, 400),
      (639, 448),
      (640, 448),
      (760, 520),
      (1200, 900),
      (2048, 2048),
    ] {
    ignore((app.resize)(width, height))
    let controls = (app.view)()
    for i, control in controls {
      let a = control.element.bounds
      assert_true(a.x >= 0 && a.y >= 0 && a.width > 0 && a.height > 0)
      assert_true(a.x + a.width <= width && a.y + a.height <= height)
      assert_true(a.width <= 1024 && a.height <= 1024)
      for j in (i + 1)..<controls.length() {
        let b = controls[j].element.bounds
        assert_true(
          a.x + a.width <= b.x ||
          b.x + b.width <= a.x ||
          a.y + a.height <= b.y ||
          b.y + b.height <= a.y,
        )
      }
    }
  }
  (app.stop)()
}
