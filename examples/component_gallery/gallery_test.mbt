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
