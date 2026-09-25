///|
async fn verify_viewport() -> Unit {
  let tree = @semantics.empty(905, 1)
  let rows = Array::makei(8, index => {
    @semantics.add_button(tree, "Row " + (index + 1).to_string()).unwrap()
  })
  let list = @layout.VerticalList::new(row_height=36, gap=4).unwrap()
  let clip : Ref[@view.Bounds] = Ref({ x: 16, y: 30, width: 180, height: 100, })
  let activated = Ref(0)
  let finished = Ref(false)
  let observed : Ref[@window_host.Observation?] = Ref(None)
  let portable : @portable.Application = {
    title: "Viewport probe",
    editor: tree,
    default_input: None,
    initial_size: (480, 240),
    publications: None,
    downstreams: None,
    serials: None,
    components: None,
    connect_tasks: _ => (),
    initialize: () => None,
    viewport: Some({
      scroll: (x, y, delta) => list.scroll_at(x, y, delta),
      reveal: reference => list.reveal(reference),
    }),
    view: () => {
      list.arrange(clip.val, rows).unwrap()
      list
      .items()
      .map(placement => {
        let node = @semantics.node(tree, placement.reference).unwrap()
        @portable.Control::{
          element: {
            bounds: placement.bounds,
            text: node.name,
            reference: Some(node.reference),
            focused: node.focused,
          },
          kind: Button,
          clip: Some(clip.val),
        }
      })
    },
    activate: _ => {
      activated.val += 1
      None
    },
    edited: _ => None,
    resize: (_, height) => {
      let limit = if height <= 240 { 100 } else { 800 }
      clip.val = { ..clip.val, height: (height - 60).max(36).min(limit), }
      true
    },
    stop: () => ignore(@semantics.dispose(tree)),
    can_close: () => true,
    close_requested: () => (),
    close_ready: () => false,
    input_error: _ => (),
    dispose: () => (),
  }
  let app = @host_application.from_application(portable)
  @window_host.run(
    app,
    hidden=true,
    observer=Some(value => observed.val = Some(value)),
    controller=Some(handle => {
      @async.with_timeout(10000, () => {
        while observed.val is None {
          @async.sleep(1)
        }
        let observe = observed.val.unwrap()
        let initial = (handle.capture)(_ => ())
        assert_eq((app.view)().accessibility.controls.length(), 8)
        assert_eq((app.view)().accessibility.controls[7].bounds.height, 0)
        let window = observe.hwnd
        drag_message(window, 0x201U, 1UL, 40, 170)
        drag_message(window, 0x202U, 0UL, 40, 170)
        drag_barrier(handle)
        assert_eq(activated.val, 0)
        drag_message(window, 0x201U, 1UL, 40, 40)
        drag_message(window, 0x202U, 0UL, 40, 40)
        drag_barrier(handle)
        assert_eq(activated.val, 1)
        let before = (handle.inspect)().frames
        assert_true(
          pointer_post(window, 0x200U, 0UL, (50 * 65536 + 40).to_int64()) != 0,
        )
        assert_true(pointer_post(window, 0x20AU, 0xFF880000UL, 0L) != 0)
        while (handle.inspect)().frames <= before {
          @async.sleep(5)
        }
        let moved = (handle.capture)(_ => ())
        assert_true(moved.pixels != initial.pixels)
        assert_true(list.items()[0].bounds.y < 30)
        for y in 132..<210 {
          for x in 16..<196 {
            for channel in 0..<4 {
              let pixel = (y * 480 + x) * 4 + channel
              assert_eq(moved.pixels[pixel], initial.pixels[pixel])
            }
          }
        }
        assert_true(@semantics.node(tree, rows[0]).unwrap().focused)
        for index in 1..<8 {
          assert_true(pointer_post(window, 0x100U, 9UL, 0L) != 0)
          assert_true(pointer_post(window, 0x101U, 9UL, 0L) != 0)
          while !@semantics.node(tree, rows[index]).unwrap().focused {
            @async.sleep(5)
          }
          drag_barrier(handle)
        }
        assert_true(@semantics.node(tree, rows[7]).unwrap().focused)
        let last = list.items()[7]
        assert_eq(last.visible, Some(last.bounds))
        assert_eq((app.view)().accessibility.controls[7].bounds, last.bounds)
        (observe.resize)(480, 120)
        while clip.val.height != 60 {
          @async.sleep(5)
        }
        (observe.draw)()
        let resized = list.items()[7]
        assert_eq(resized.visible, Some(resized.bounds))
        assert_true(resized.bounds.y + resized.bounds.height <= 90)
        for index in 8..<20 {
          rows.push(
            @semantics.add_button(tree, "Row " + (index + 1).to_string()).unwrap(),
          )
        }
        (observe.resize)(480, 900)
        while clip.val.height != 800 {
          @async.sleep(5)
        }
        (observe.draw)()
        assert_eq((app.view)().accessibility.controls.length(), 20)
        assert_eq(list.items()[19].visible, Some(list.items()[19].bounds))
        ignore((handle.capture)(_ => ()))
        finished.val = true
        (handle.apply)(Close)
      })
    }),
  )
  assert_true(finished.val)
  println(
    "NATIVE_VIEWPORT_OK clipping hidden_hit wheel retained_rows tab_reveal resize accessibility_bounds twenty_layers",
  )
}
