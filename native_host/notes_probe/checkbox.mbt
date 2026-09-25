///|
async fn verify_checkbox_gallery() -> Unit {
  let app = @gallery.create()
  let observed : Ref[@window_host.Observation?] = Ref(None)
  let finished = Ref(false)
  let find = (name : String) => {
    @semantics.snapshot(app.editor)
    .iter()
    .find_first(node => node.name == name)
    .unwrap()
  }
  @window_host.run(
    @host_application.from_application(app),
    hidden=true,
    observer=Some(value => observed.val = Some(value)),
    controller=Some(handle => {
      @async.with_timeout(10000, () => {
        while observed.val is None {
          @async.sleep(1)
        }
        let window = observed.val.unwrap().hwnd
        let initial = (handle.capture)(_ => ())
        assert_true(find("Checked").checked)
        assert_false(find("Unchecked").checked)
        assert_false(find("Disabled").enabled)
        assert_true(find("Error").invalid)
        assert_eq(
          (app.view)()
          .filter(control => control.kind == @portable.Checkbox)
          .length(),
          5,
        )
        drag_message(window, 0x201U, 1UL, 42, 85)
        drag_message(window, 0x202U, 0UL, 42, 85)
        drag_barrier(handle)
        assert_true(find("Unchecked").checked)
        assert_true(find("Unchecked").focused)
        let checked = (handle.capture)(_ => ())
        assert_true(checked.pixels != initial.pixels)
        assert_true(pointer_post(window, 0x100U, 32UL, 0L) != 0)
        assert_true(pointer_post(window, 0x101U, 32UL, 0L) != 0)
        drag_barrier(handle)
        assert_false(find("Unchecked").checked)
        drag_message(window, 0x201U, 1UL, 42, 133)
        drag_message(window, 0x202U, 0UL, 42, 133)
        drag_barrier(handle)
        assert_false(find("Disabled").checked)
        let old = find("Dynamic").reference
        drag_message(window, 0x201U, 1UL, 42, 277)
        drag_message(window, 0x202U, 0UL, 42, 277)
        drag_barrier(handle)
        assert_true(@semantics.node(app.editor, old) is Err("stale_target"))
        drag_message(window, 0x201U, 1UL, 42, 229)
        drag_message(window, 0x202U, 0UL, 42, 229)
        drag_barrier(handle)
        assert_true(find("Dynamic").reference != old)
        finished.val = true
        (handle.apply)(Close)
      })
    }),
  )
  assert_true(finished.val)
  println(
    "NATIVE_CHECKBOX_OK pointer space disabled invalid keyed_recreate pixels",
  )
}
