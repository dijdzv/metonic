///|
fn reference(id : Int, generation? : Int = 1) -> @semantics.NodeRef {
  { session: 1, window: 1, id, generation, }
}

///|
test "scroll clips partial rows and reveals retained offscreen identities" {
  let list = @layout.VerticalList::new(row_height=40, gap=8).unwrap()
  let a = reference(1)
  let b = reference(2)
  let c = reference(3)
  let viewport : @view.Bounds = { x: 20, y: 30, width: 200, height: 80, }
  list.arrange(viewport, [a, b, c]).unwrap()
  assert_eq(list.items().length(), 3)
  assert_eq(list.items()[2].visible, None)
  assert_eq(
    list.items()[1].visible,
    Some({ x: 20, y: 78, width: 200, height: 32, }),
  )
  assert_eq(list.hit(25, 109), Some(b))
  assert_eq(list.hit(25, 110), None)
  assert_true(list.reveal(c))
  assert_eq(
    list.items()[2].visible,
    Some({ x: 20, y: 70, width: 200, height: 40, }),
  )
  assert_eq(list.items()[0].visible, None)
  let scrolled = list.items()
  list.arrange(viewport, [a, b, c]).unwrap()
  assert_eq(list.items(), scrolled)
  assert_false(list.scroll(2147483647))
  assert_true(list.scroll(-2147483647))
  assert_eq(list.items()[0].bounds.y, 30)
  assert_false(list.reveal(reference(4)))
}

///|
test "reorder resize and removal retain references and clamp scroll" {
  let list = @layout.VerticalList::new(row_height=40, gap=8).unwrap()
  let a = reference(1)
  let b = reference(2)
  let c = reference(3)
  list.arrange({ x: 0, y: 0, width: 100, height: 80, }, [a, b, c]).unwrap()
  ignore(list.reveal(c))
  list.arrange({ x: 0, y: 0, width: 300, height: 120, }, [c, b]).unwrap()
  assert_eq(list.items().map(p => p.reference), [c, b])
  assert_eq(list.items()[1].bounds, { x: 0, y: 48, width: 300, height: 40, })
  assert_eq(list.hit(299, 49), Some(b))
  list.arrange({ x: 0, y: 0, width: 300, height: 120, }, []).unwrap()
  assert_eq(list.items(), [])
  assert_false(list.scroll(40))
}

///|
test "invalid updates preserve the last valid layout and generations are distinct" {
  let list = @layout.VerticalList::new(row_height=40).unwrap()
  let a = reference(1)
  let renewed = reference(1, generation=2)
  let viewport : @view.Bounds = { x: 0, y: 0, width: 100, height: 80, }
  list.arrange(viewport, [a, renewed]).unwrap()
  let before = list.items()
  assert_eq(list.arrange(viewport, [a, a]), Err("duplicate_list_reference"))
  assert_eq(list.items(), before)
  assert_eq(
    list.arrange({ ..viewport, width: 0, }, []),
    Err("invalid_list_bounds"),
  )
  assert_eq(list.items(), before)
}
