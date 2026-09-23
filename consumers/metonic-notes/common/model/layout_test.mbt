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

///|
async test "view keeps only viewport rows while scrolling preserves logical identity" {
  let mut document = @collection.empty()
  for _ in 0..<60 {
    let (next, id) = document.create_note().unwrap()
    document = next.edit(id, "Memo text").unwrap()
  }
  let app = create_collection(
    { load: () => Ok(Some(document.encode())), save: _ => Ok(()), },
    () => (),
    _ => (),
  )
  finish((app.initialize)())
  let row_refs = () => {
    (app.view)()
    .filter(control => {
      control.kind == @application.Button &&
      control.element.text.contains("Memo ")
    })
    .map(control => control.element.reference.unwrap())
  }
  let first = row_refs()
  assert_true(first.length() > 0 && first.length() < 32)
  assert_true((app.viewport.unwrap().scroll)(40, 200, 720))
  let later = row_refs()
  assert_true(later.length() > 0 && later.length() < 32)
  assert_false(later.contains(first[0]))
  assert_true(@semantics.node(app.editor, first[0]) is Ok(_))
  assert_true((app.viewport.unwrap().scroll)(40, 200, -720))
  assert_eq(row_refs()[0], first[0])
  (app.stop)()
}
