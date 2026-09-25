///|
async fn verify_keyed() -> Unit {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(929, 1)
  let children : @component.KeyedChildren[Int, String, @semantics.NodeRef] = @component.KeyedChildren::new(
    root, tree,
  )
  let disposed = Ref(0)
  let create = (owner : @component.ChildOwner, _ : Int, label : String) => {
    owner.scope().on_dispose(() => disposed.val += 1)
    owner.add_input(label, "abc").unwrap()
  }
  let update = (reference : @semantics.NodeRef, label : String) => {
    ignore(@semantics.set_name(tree, reference, label))
  }
  assert_true(
    children.reconcile(
      [{ key: 1, props: "One", }, { key: 2, props: "Two", }],
      create,
      update,
    ),
  )
  let first = children.get(1).unwrap()
  let second = children.get(2).unwrap()
  let app : @portable.Application = {
    title: "Keyed component probe",
    editor: tree,
    default_input: None,
    initial_size: (480, 280),
    viewport: None,
    publications: None,
    downstreams: None,
    serials: None,
    components: None,
    connect_tasks: _ => (),
    initialize: () => None,
    view: () => {
      let controls : Array[@portable.Control] = []
      for index, reference in children.ordered() {
        let node = @semantics.node(tree, reference).unwrap()
        controls.push({
          element: {
            reference: Some(reference),
            text: node.value,
            focused: node.focused,
            bounds: { x: 16, y: 16 + index * 54, width: 300, height: 44, },
          },
          kind: Input(single_line=true),
          clip: None,
        })
      }
      controls
    },
    activate: _ => None,
    edited: _ => None,
    resize: (_, _) => false,
    stop: () => {
      ignore(children.clear())
      root.dispose()
      ignore(@semantics.dispose(tree))
    },
    can_close: () => true,
    close_requested: () => (),
    close_ready: () => false,
    input_error: _ => (),
    dispose: () => (),
  }
  let finished = Ref(false)
  let observed : Ref[@window_host.Observation?] = Ref(None)
  @window_host.run(
    @host_application.from_application(app),
    hidden=true,
    observer=Some(state => observed.val = Some(state)),
    controller=Some(handle => {
      @async.with_timeout(5000, () => {
        while observed.val is None {
          @async.sleep(1)
        }
        let draw = observed.val.unwrap().draw
        let original = (handle.capture)(_ => ())
        assert_eq(@semantics.focus(tree, first), "")
        assert_eq(@semantics.set_selection(tree, first, 1, 2), "")
        assert_true(
          children.reconcile(
            [{ key: 2, props: "Two", }, { key: 1, props: "One", }],
            create,
            update,
          ),
        )
        draw()
        assert_eq(children.ordered(), [second, first])
        assert_eq(children.get(1), Some(first))
        let retained = @semantics.node(tree, first).unwrap()
        assert_true(retained.focused)
        assert_eq((retained.selection_start, retained.selection_end), (1, 2))
        assert_eq(disposed.val, 0)
        let reordered = (handle.capture)(_ => ())
        assert_true(reordered.pixels != original.pixels)
        assert_true(
          children.reconcile([{ key: 2, props: "Two", }], create, update),
        )
        draw()
        assert_eq(disposed.val, 1)
        assert_true(children.for_reference(first) is None)
        assert_true(@semantics.node(tree, first) is Err(_))
        assert_true(
          children.reconcile(
            [{ key: 2, props: "Two", }, { key: 1, props: "One", }],
            create,
            update,
          ),
        )
        draw()
        let recreated = children.get(1).unwrap()
        assert_true(recreated != first)
        assert_false(@semantics.node(tree, recreated).unwrap().focused)
        assert_true(children.for_reference(first) is None)
        assert_eq(children.for_reference(recreated), Some(recreated))
        let restored = (handle.capture)(_ => ())
        assert_true(restored.pixels != reordered.pixels)
        (handle.apply)(Close)
        finished.val = true
      })
    }),
  )
  assert_true(finished.val)
  assert_eq(disposed.val, 3)
}
