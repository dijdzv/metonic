///|
async test "memo rows exist only for visible records and retain surviving identities" {
  let app = create_collection(
    { load: () => Ok(None), save: _ => Ok(()), },
    () => (),
    _ => (),
  )
  initialize(app)
  assert_eq((app.view)().length(), 10)
  let activate = index => {
    ignore((app.activate)((app.view)()[index].element.reference.unwrap()))
  }
  activate(3)
  let first = (app.view)()[7].element.reference.unwrap()
  activate(3)
  let second = (app.view)()[8].element.reference.unwrap()
  assert_eq((app.view)()[7].element.reference, Some(first))
  activate(7)
  activate(4)
  activate(4)
  assert_eq((app.view)().length(), 11)
  assert_eq((app.view)()[7].element.reference, Some(second))
  assert_true(@semantics.node(app.editor, first) is Err(_))
  assert_true((app.activate)(first) is None)
  assert_eq((app.view)()[7].element.reference, Some(second))
  activate(4)
  activate(4)
  assert_eq((app.view)().length(), 10)
  assert_true(@semantics.node(app.editor, second) is Err(_))
  activate(3)
  let replacement = (app.view)()[7].element.reference.unwrap()
  assert_true(replacement != first && replacement != second)
  (app.stop)()
}

///|
async test "overflow, real reorder and deletion preserve the right memo identities" {
  let saved : Ref[String?] = Ref(None)
  let app = create_collection(
    {
      load: () => Ok(saved.val),
      save: value => {
        saved.val = Some(value)
        Ok(())
      },
    },
    () => (),
    _ => (),
  )
  initialize(app)
  let action = index => (app.view)()[index].element.reference.unwrap()
  let new_memo = action(3)
  for _ in 0..<10 {
    ignore((app.activate)(new_memo))
  }
  let rows = () => {
    (app.view)().filter(control => control.element.text.contains("Memo "))
  }
  let list_bounds = rows()[0].clip.unwrap()
  assert_true(
    (app.viewport.unwrap().scroll)(list_bounds.x + 1, list_bounds.y + 1, -10000),
  )
  let original = rows().map(control => control.element.reference.unwrap())
  assert_true(original.length() > 6 && original.length() < 10)
  assert_eq(rows()[0].visible_bounds(), Some(rows()[0].element.bounds))
  assert_true(
    (app.viewport.unwrap().scroll)(list_bounds.x + 1, list_bounds.y + 1, 10000),
  )
  assert_false(
    rows()
    .map(control => control.element.reference.unwrap())
    .contains(original[0]),
  )
  assert_true(
    (app.viewport.unwrap().scroll)(list_bounds.x + 1, list_bounds.y + 1, -10000),
  )
  assert_eq(rows().map(control => control.element.reference.unwrap()), original)
  ignore((app.activate)(original[5]))
  ignore((app.activate)(action(5)))
  let reordered = rows().map(control => control.element.reference.unwrap())
  assert_eq(reordered[4], original[5])
  assert_eq(reordered[5], original[4])
  assert_eq(reordered[0], original[0])
  finish((app.activate)(action(1)))
  assert_eq(
    @collection.decode(saved.val).unwrap().items().map(note => note.id),
    [1, 2, 3, 4, 6, 5, 7, 8, 9, 10],
  )
  ignore((app.activate)(action(4)))
  ignore((app.activate)(action(4)))
  assert_true(rows().length() < 9)
  assert_true(@semantics.node(app.editor, original[5]) is Err(_))
  assert_true(@semantics.node(app.editor, original[4]) is Ok(_))
  (app.stop)()
}
