///|
async test "gallery exposes checked, disabled, invalid and recreated checkboxes" {
  let app = create()
  let named = (name : String) => {
    @semantics.snapshot(app.editor)
    .iter()
    .find_first(node => node.name == name)
    .unwrap()
  }
  let initial = (app.view)()
  assert_eq(
    initial.filter(control => control.kind == @app.Checkbox).length(),
    5,
  )
  assert_true(named("Checked").checked)
  assert_false(named("Unchecked").checked)
  assert_false(named("Disabled").enabled)
  assert_true(named("Error").invalid)
  let unchecked = named("Unchecked").reference
  ignore((app.activate)(unchecked))
  assert_true(app.synchronize_components(None))
  assert_true(named("Unchecked").checked)
  let disabled = named("Disabled").reference
  ignore((app.activate)(disabled))
  assert_false(named("Disabled").checked)
  let old = named("Dynamic").reference
  let toggle = named("Toggle dynamic").reference
  ignore((app.activate)(toggle))
  assert_true(@semantics.node(app.editor, old) is Err("stale_target"))
  assert_eq(
    (app.view)().filter(control => control.kind == @app.Checkbox).length(),
    4,
  )
  ignore((app.activate)(toggle))
  let fresh = named("Dynamic").reference
  assert_true(fresh != old)
  ignore((app.activate)(old))
  assert_false(named("Dynamic").checked)
  (app.dispose)()
}

///|
test "gallery list retains keyed rows and selection through reorder and scrolling" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(916, 1)
  let ui = @component.UiRoot::new(scope, tree)
  let gallery = Gallery::new(ui)
  let initial = gallery.list.items()
  assert_eq(initial.length(), 12)
  assert_eq(
    @semantics.node(tree, gallery.list.reference()).unwrap().role,
    @semantics.List,
  )
  assert_true(@semantics.node(tree, initial[0].reference()).unwrap().selected)
  assert_false(@semantics.node(tree, initial[4].reference()).unwrap().enabled)
  let rows = gallery.list_rows.peek().copy()
  rows.insert(0, { key: "inserted", label: "Inserted", enabled: true, })
  gallery.set_list_rows(rows)
  assert_eq(gallery.list.items()[0].reference(), initial[0].reference())
  assert_true(ui.synchronize(None))
  assert_eq(gallery.list.items()[1].reference(), initial[0].reference())
  let reversed = rows.rev()
  gallery.set_list_rows(reversed)
  assert_true(ui.synchronize(None))
  assert_eq(
    gallery.list.items()[reversed.length() - 2].reference(),
    initial[0].reference(),
  )
  assert_true(@semantics.node(tree, initial[0].reference()).unwrap().selected)
  let controls = gallery.view()
  assert_eq(controls.filter(control => control.kind == @app.List).length(), 1)
  assert_eq(
    controls.filter(control => control.kind == @app.ListItem).length(),
    13,
  )
  let last = gallery.list.items()[12].reference()
  let viewport = gallery.list_view.viewport()
  assert_true((viewport.reveal)(last))
  let visible = gallery
    .view()
    .iter()
    .find_first(control => control.element.reference == Some(last))
    .unwrap()
  assert_true(visible.visible_bounds() is Some(_))
  assert_true((viewport.scroll)(30, 450, -52))
  scope.dispose()
}

///|
test "gallery list revokes deleted rows before late activation" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(917, 1)
  let ui = @component.UiRoot::new(scope, tree)
  let gallery = Gallery::new(ui)
  let old = gallery.list.items()[0].reference()
  ignore(ui.activate(old))
  assert_eq(gallery.list_selection.peek(), Some("item-0"))
  let remaining = gallery.list_rows.peek().filter(row => row.key != "item-0")
  gallery.set_list_rows(remaining)
  assert_true(ui.synchronize(None))
  assert_eq(gallery.list_selection.peek(), None)
  assert_true(@semantics.node(tree, old) is Err("stale_target"))
  ignore(ui.activate(old))
  assert_eq(gallery.list_selection.peek(), None)
  let restored = [
    @component.ListRow::{ key: "item-0", label: "Recreated", enabled: true, },
  ]
  restored.append(remaining)
  gallery.set_list_rows(restored)
  assert_true(ui.synchronize(None))
  assert_true(gallery.list.items()[0].reference() != old)
  ignore(ui.activate(old))
  assert_eq(gallery.list_selection.peek(), None)
  scope.dispose()
}

///|
async test "gallery status changes phase without changing identity and retry stays a button" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(918, 1)
  let ui = @component.UiRoot::new(scope, tree)
  let gallery = Gallery::new(ui)
  let status = gallery.status.reference()
  assert_eq(@semantics.node(tree, status).unwrap().role, @semantics.Status)
  assert_eq(
    @semantics.node(tree, gallery.retry.reference()).unwrap().role,
    @semantics.Button,
  )
  gallery.status_value.set(
    @component.StatusState::RetainedPrevious("Quote: loading", "112"),
  )
  assert_true(ui.synchronize(None))
  assert_eq(
    @semantics.node(tree, status).unwrap().name,
    "Quote: loading (previous 112)",
  )
  gallery.status_value.set(@component.StatusState::Failed("Quote: failed"))
  assert_true(ui.synchronize(None))
  assert_true(@semantics.node(tree, status).unwrap().invalid)
  let retry = ui.activate(gallery.retry.reference()).unwrap()
  assert_true(ui.synchronize(None))
  assert_eq(@semantics.node(tree, status).unwrap().name, "Quote: loading")
  assert_false(@semantics.node(tree, status).unwrap().invalid)
  retry.invalidate()
  assert_eq(retry.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(ui.synchronize(None))
  assert_eq(@semantics.node(tree, status).unwrap().name, "Quote: 112")
  assert_true(
    gallery
    .view()
    .any(control => {
      control.kind == @app.Status && control.element.reference == Some(status)
    }),
  )
  scope.dispose()
  assert_true(@semantics.node(tree, status) is Err("stale_target"))
}

///|
test "gallery theme, text inputs and row order follow one owner boundary" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(919, 1)
  let ui = @component.UiRoot::new(scope, tree)
  let gallery = Gallery::new(ui)
  assert_eq(
    @semantics.node(tree, gallery.heading.reference()).unwrap().role,
    @semantics.Label,
  )
  assert_false(
    @semantics.node(tree, gallery.disabled_input.reference()).unwrap().enabled,
  )
  assert_false(
    @semantics.node(tree, gallery.disabled_button.reference()).unwrap().enabled,
  )
  assert_eq(
    @semantics.node(tree, gallery.multi.reference()).unwrap().value,
    "First line\nSecond line",
  )
  assert_eq(
    @semantics.set_text(tree, gallery.single.reference(), "new key"),
    "",
  )
  ignore(
    ui.edited(gallery.single.reference(), "new key", @semantics.revision(tree)),
  )
  assert_eq(gallery.single_value.peek(), "new key")
  let first = gallery.list.items()[0].reference()
  ignore(ui.activate(gallery.rotate.reference()))
  assert_eq(gallery.list.items()[0].reference(), first)
  assert_true(ui.synchronize(None))
  assert_eq(gallery.list.items()[11].reference(), first)
  assert_true(@semantics.node(tree, first).unwrap().selected)
  assert_eq(ui.theme(), @theme.default())
  ignore(ui.activate(gallery.theme_toggle.reference()))
  assert_eq(ui.theme().border, @theme.Rgb::{
    red: b'\x63',
    green: b'\x45',
    blue: b'\x91',
  })
  assert_true(ui.synchronize(None))
  assert_false(ui.synchronize(None))
  ignore(ui.activate(gallery.theme_toggle.reference()))
  assert_eq(ui.theme(), @theme.default())
  assert_true(ui.synchronize(None))
  scope.dispose()
}
