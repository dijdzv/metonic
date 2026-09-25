///|
async fn verify_no_input() -> Unit {
  let tree = @semantics.empty(720, 1)
  let button = @semantics.add_button(tree, "Action").unwrap()
  let input : Ref[@semantics.NodeRef?] = Ref(None)
  let activated = Ref(0)
  let edited = Ref(0)
  let disposed = Ref(0)
  let finished = Ref(false)
  let observation : Ref[@window_host.Observation?] = Ref(None)
  let app : @portable.Application = {
    title: "No input application",
    editor: tree,
    default_input: None,
    initial_size: (480, 240),
    viewport: None,
    publications: None,
    downstreams: None,
    serials: None,
    components: None,
    connect_tasks: _ => (),
    initialize: () => None,
    view: () => {
      let controls : Array[@portable.Control] = [
        {
          element: {
            reference: Some(button),
            text: "Action",
            focused: @semantics.node(tree, button).unwrap().focused,
            bounds: { x: 16, y: 16, width: 160, height: 40, },
          },
          kind: Button,
          clip: None,
        },
      ]
      if input.val is Some(reference) {
        let node = @semantics.node(tree, reference).unwrap()
        controls.push({
          element: {
            reference: Some(reference),
            text: node.value,
            focused: node.focused,
            bounds: { x: 16, y: 70, width: 400, height: 80, },
          },
          kind: Input(single_line=false),
          clip: None,
        })
      }
      controls
    },
    activate: reference => {
      if reference == button {
        activated.val += 1
      }
      None
    },
    resize: (_, _) => false,
    stop: () => ignore(@semantics.dispose(tree)),
    can_close: () => true,
    close_requested: () => (),
    close_ready: () => false,
    input_error: _ => (),
    edited: _ => {
      edited.val += 1
      None
    },
    dispose: () => disposed.val += 1,
  }
  @window_host.run(
    @host_application.from_application(app),
    hidden=true,
    observer=Some(state => observation.val = Some(state)),
    controller=Some(handle => {
      @async.with_timeout(5000, () => {
        while observation.val is None {
          @async.sleep(1)
        }
        let observe = observation.val.unwrap()
        let initial = (handle.inspect)()
        assert_eq(initial.default_input, None)
        assert_eq(initial.controls.length(), 1)
        assert_true(initial.frames > 0)
        assert_eq((handle.edit)(Some("ignored"), None), "no_default_input")
        assert_eq((handle.select)(0, 0, None), "no_default_input")
        (handle.apply)(Insert("ignored"))
        (handle.apply)(Backspace)
        assert_eq((handle.inspect)().controls.length(), 1)
        assert_eq(
          (handle.operate)(button, ActivateControl, @semantics.revision(tree)),
          "",
        )
        assert_eq(activated.val, 1)

        let reference = @semantics.add_input(tree, "Temporary", "日本語").unwrap()
        input.val = Some(reference)
        assert_eq(@semantics.focus(tree, reference), "")
        (handle.apply)(Insert("X"))
        assert_eq(@semantics.node(tree, reference).unwrap().value, "日本語X")
        assert_eq(edited.val, 1)
        input.val = None
        (handle.apply)(Insert("hidden"))
        assert_eq(@semantics.node(tree, reference).unwrap().value, "日本語X")
        input.val = Some(reference)
        assert_eq(@semantics.set_enabled(tree, reference, false), "")
        (handle.apply)(Insert("disabled"))
        assert_eq(@semantics.node(tree, reference).unwrap().value, "日本語X")
        assert_eq(@semantics.set_enabled(tree, reference, true), "")
        assert_eq(@semantics.focus(tree, reference), "")
        (observe.inject)(CompositionStart)
        (handle.apply)(Move(0, 0))
        assert_true((handle.inspect)().composing)
        assert_eq(@semantics.remove(tree, reference), "")
        input.val = None
        (observe.draw)()
        assert_false((handle.inspect)().composing)
        let replacement = @semantics.restore_input(
          tree,
          reference.id,
          "Replacement",
          "safe",
        ).unwrap()
        input.val = Some(replacement)
        assert_true(replacement.generation != reference.generation)
        assert_eq(@semantics.focus(tree, replacement), "")
        (observe.inject)(CompositionUpdate("late preview", None))
        (handle.apply)(Insert("late commit"))
        assert_eq(@semantics.node(tree, replacement).unwrap().value, "safe")
        assert_eq(edited.val, 1)
        assert_false((handle.inspect)().composing)
        (observe.inject)(CompositionEnd)
        (handle.apply)(Insert("!"))
        assert_eq(@semantics.node(tree, replacement).unwrap().value, "safe!")
        assert_eq(edited.val, 2)
        assert_eq(@semantics.remove(tree, replacement), "")
        input.val = None
        assert_eq(
          (handle.operate)(button, ActivateControl, @semantics.revision(tree)),
          "",
        )
        (handle.apply)(Insert("late"))
        assert_eq((handle.inspect)().default_input, None)
        assert_eq((handle.inspect)().controls.length(), 1)
        assert_false((handle.inspect)().composing)
        assert_eq(activated.val, 2)
        assert_eq(edited.val, 2)
        let frame = (handle.capture)(_ => ())
        assert_eq(frame.pixels.length(), 480 * 240 * 4)
        finished.val = true
        (handle.apply)(Close)
      })
    }),
  )
  assert_true(finished.val)
  assert_eq(disposed.val, 1)
  println("NO_INPUT_APPLICATION_OK")
}

///|
async fn verify_empty_view() -> Unit {
  let empty_tree = @semantics.empty(721, 1)
  let empty_finished = Ref(false)
  let empty_disposed = Ref(0)
  let empty_app : @portable.Application = {
    title: "Empty application",
    editor: empty_tree,
    default_input: None,
    initial_size: (480, 240),
    viewport: None,
    publications: None,
    downstreams: None,
    serials: None,
    components: None,
    connect_tasks: _ => (),
    initialize: () => None,
    view: () => [],
    activate: _ => None,
    resize: (_, _) => false,
    can_close: () => true,
    close_requested: () => (),
    close_ready: () => false,
    input_error: _ => (),
    edited: _ => None,
    stop: () => ignore(@semantics.dispose(empty_tree)),
    dispose: () => empty_disposed.val += 1,
  }
  @window_host.run(
    @host_application.from_application(empty_app),
    hidden=true,
    controller=Some(handle => {
      @async.with_timeout(5000, () => {
        assert_eq((handle.inspect)().controls.length(), 0)
        assert_eq((handle.inspect)().default_input, None)
        (handle.apply)(Insert("ignored"))
        (handle.apply)(Activate)
        (handle.apply)(Move(1, 1))
        let capture = (handle.capture)(_ => ())
        assert_true(capture.state.frames > 0)
        assert_eq(capture.pixels.length(), 480 * 240 * 4)
        empty_finished.val = true
        (handle.apply)(Close)
      })
    }),
  )
  assert_true(empty_finished.val)
  assert_eq(empty_disposed.val, 1)
  println("EMPTY_APPLICATION_OK")
}
