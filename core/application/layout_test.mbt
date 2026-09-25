///|
test "stack keeps owned widget identity through resize and reorder" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(91, 1)
  let owner = @component.UiRoot::new(scope, tree).fixed("actions")
  let first = owner.button("first", "First", () => None).unwrap()
  let second = owner.button("second", "Second", () => None).unwrap()
  let stack = Stack::new(@layout.Horizontal, gap=8)
  let bounds : @view.Bounds = { x: 0, y: 0, width: 160, height: 40, }
  let items = [
    StackItem::new(@layout.Fixed(40), Widget::button(first)),
    StackItem::new(@layout.Fixed(40), Widget::button(second)),
  ]
  let initial = stack.arrange(bounds, items).unwrap()
  assert_eq(initial.map(control => control.element.bounds.x), [0, 48])
  assert_eq(initial[0].element.reference, Some(first.reference()))
  assert_eq(initial[1].element.reference, Some(second.reference()))
  let reordered = stack
    .arrange({ ..bounds, width: 240, }, [items[1], items[0]])
    .unwrap()
  assert_eq(reordered[0].element.reference, Some(second.reference()))
  assert_eq(reordered[1].element.reference, Some(first.reference()))
  assert_eq(reordered.map(control => control.element.bounds.x), [0, 48])
  assert_eq(@semantics.snapshot(tree).length(), 2)
  scope.dispose()
}

///|
test "scroll view clips, scrolls and reveals owned controls" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(92, 1)
  let owner = @component.UiRoot::new(scope, tree).fixed("rows")
  let first = owner.button("first", "First", () => None).unwrap()
  let second = owner.button("second", "Second", () => None).unwrap()
  let third = owner.button("third", "Third", () => None).unwrap()
  let rows = [
    ScrollItem::new(40, Widget::button(first)),
    ScrollItem::new(40, Widget::button(second)),
    ScrollItem::new(40, Widget::button(third)),
  ]
  let scroll = ScrollView::new(gap=8).unwrap()
  let bounds : @view.Bounds = { x: 10, y: 20, width: 120, height: 60, }
  let initial = scroll.arrange(bounds, rows).unwrap()
  assert_eq(
    initial[0].visible_bounds(),
    Some({ x: 10, y: 20, width: 120, height: 40, }),
  )
  assert_eq(
    initial[1].visible_bounds(),
    Some({ x: 10, y: 68, width: 120, height: 12, }),
  )
  assert_eq(initial[2].visible_bounds(), None)
  let viewport = scroll.viewport()
  assert_false((viewport.scroll)(0, 0, 48))
  assert_true((viewport.scroll)(20, 30, 48))
  let moved = scroll.arrange(bounds, rows).unwrap()
  assert_eq(moved[1].element.bounds.y, 20)
  assert_true((viewport.reveal)(third.reference()))
  let revealed = scroll.arrange(bounds, rows).unwrap()
  assert_eq(revealed[2].visible_bounds(), Some(revealed[2].element.bounds))
  scope.dispose()
}

///|
test "scroll view preserves keyed variable-height controls and revokes removed rows" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(93, 1)
  let ui = @component.UiRoot::new(scope, tree)
  let first_owner = ui.fixed("first")
  let second_owner = ui.fixed("second")
  let third_owner = ui.fixed("third")
  let first = first_owner.button("action", "First", () => None).unwrap()
  let second = second_owner.button("action", "Second", () => None).unwrap()
  let third = third_owner.button("action", "Third", () => None).unwrap()
  let scroll = ScrollView::new(gap=4).unwrap()
  let bounds : @view.Bounds = { x: 4, y: 8, width: 100, height: 60, }
  let a = ScrollItem::new(20, Widget::button(first))
  let b = ScrollItem::new(36, Widget::button(second))
  let c = ScrollItem::new(48, Widget::button(third))
  let initial = scroll.arrange(bounds, [a, b, c]).unwrap()
  assert_eq(initial.map(control => control.element.bounds.y), [8, 32, 72])
  assert_true((scroll.viewport().scroll)(10, 20, 32))
  let moved = scroll.arrange(bounds, [c, a, b]).unwrap()
  assert_eq(moved.map(control => control.element.reference), [
    Some(third.reference()),
    Some(first.reference()),
    Some(second.reference()),
  ])
  assert_eq(moved.map(control => control.element.bounds.height), [48, 20, 36])
  second_owner.scope().dispose()
  let remaining = scroll.arrange(bounds, [c, a]).unwrap()
  assert_eq(remaining.length(), 2)
  assert_false((scroll.viewport().reveal)(second.reference()))
  assert_eq(@semantics.snapshot(tree).length(), 2)
  scope.dispose()
}
