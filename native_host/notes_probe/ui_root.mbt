///|
async fn verify_ui_root() -> Unit {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(725, 1)
  let ui = @component.UiRoot::new(scope, tree)
  let value = @reactive.Signal::new(scope, "initial")
  let owner = ui.fixed("form")
  let input = owner
    .text_input(
      "value",
      "Controlled",
      @component.Controlled::new(() => value.peek(), text => {
        value.set(text)
        None
      }),
    )
    .unwrap()
    .reference()
  let button = owner
    .button("async", "Update async", () => {
      Some(
        @task.replace(
          () => (),
          () => {
            Some(
              @task.work(() => "async", text => {
                value.set(text)
                @task.Changed
              }),
            )
          },
          operation=@task.Operation::new(),
        ),
      )
    })
    .unwrap()
  let selected : @reactive.Signal[String?] = @reactive.Signal::new(scope, None)
  let list = owner.list("items", "Items", selected).unwrap()
  ignore(list.reconcile([{ key: "first", label: "First", enabled: true, }]))
  let list_item = list.items()[0].reference()
  let status = owner
    .label("status", @component.Read::new(() => "Status: " + value.peek()))
    .unwrap()
  let app : @portable.Application = {
    title: "Owned UI root",
    editor: tree,
    default_input: Some(input),
    initial_size: (480, 240),
    viewport: None,
    publications: None,
    downstreams: None,
    serials: None,
    components: Some(ui),
    connect_tasks: _ => (),
    initialize: () => None,
    view: () => {
      let controls : Array[@portable.Control] = [
        {
          element: {
            reference: Some(input),
            text: @semantics.node(tree, input).unwrap().value,
            focused: @semantics.node(tree, input).unwrap().focused,
            bounds: { x: 16, y: 40, width: 360, height: 48, },
          },
          kind: Input(single_line=true),
          clip: None,
        },
        @portable.button(button, { x: 16, y: 112, width: 180, height: 40, }),
        @portable.label(status, { x: 16, y: 168, width: 300, height: 30, }),
        @portable.list(list, { x: 220, y: 112, width: 180, height: 40, }),
      ]
      for item in list.items() {
        controls.push(
          @portable.list_item(item, {
            x: 220,
            y: 112,
            width: 180,
            height: 40,
          }),
        )
      }
      controls
    },
    activate: reference => ui.activate(reference),
    edited: edit => ui.edited(edit.target, edit.text, edit.revision),
    resize: (_, _) => false,
    stop: () => {
      scope.dispose()
      ignore(@semantics.dispose(tree))
    },
    can_close: () => true,
    close_requested: () => (),
    close_ready: () => false,
    input_error: _ => (),
    dispose: () => (),
  }
  let finished = Ref(false)
  @window_host.run(
    @host_application.from_application(app),
    hidden=true,
    controller=Some(handle => {
      @async.with_timeout(5000, () => {
        assert_eq(
          (handle.operate)(
            input,
            InsertText("typed"),
            @semantics.revision(tree),
          ),
          "",
        )
        assert_eq(value.peek(), "initialtyped")
        assert_eq(
          (handle.operate)(
            button.reference(),
            ActivateControl,
            @semantics.revision(tree),
          ),
          "",
        )
        while value.peek() != "async" ||
              @semantics.node(tree, input).unwrap().value != "async" {
          @async.sleep(1)
        }
        assert_eq(
          @semantics.node(tree, status.reference()).unwrap().name,
          "Status: async",
        )
        assert_eq(
          (handle.operate)(
            list_item,
            ActivateControl,
            @semantics.revision(tree),
          ),
          "",
        )
        assert_eq(selected.peek(), Some("first"))
        ignore(list.reconcile([]))
        assert_eq(selected.peek(), None)
        assert_eq(
          (handle.operate)(
            list_item,
            ActivateControl,
            @semantics.revision(tree),
          ),
          "stale_target",
        )
        let frame = (handle.capture)(_ => ())
        assert_true(frame.state.frames > 0)
        finished.val = true
        (handle.apply)(Close)
      })
    }),
  )
  assert_true(finished.val)
  println("UI_ROOT_NATIVE_OK edited async_completion synchronized")
}
