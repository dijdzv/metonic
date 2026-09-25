///|
async fn verify_serial() -> Unit {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let registry = @reactive_task.SerialRegistry::new(root)
  let tree = @semantics.empty(930, 1)
  let save = @semantics.add_button(tree, "Queue two writes").unwrap()
  let release = Ref(false)
  let started : Array[Int] = []
  let applied : Array[Int] = []
  let writer : @reactive_task.SerialTask[Int, String, String] = registry.register(
    root,
    async fn(value : String) {
      let identity = if value == "first" { 1 } else { 2 }
      started.push(identity)
      if identity == 1 {
        while !release.val {
          @async.sleep(1)
        }
      }
      Ok(value)
    },
    (job, result) => {
      if !(result is Ok(_)) {
        abort("serial write failed")
      }
      applied.push(job.identity)
    },
  )
  let app : @portable.Application = {
    title: "Serial task boundary probe",
    editor: tree,
    default_input: None,
    initial_size: (480, 240),
    viewport: None,
    publications: None,
    downstreams: None,
    serials: Some(registry),
    components: None,
    connect_tasks: control => {
      if !registry.connect(control) {
        abort("serial registry was not connected")
      }
    },
    initialize: () => None,
    view: () => {
      [
        @portable.Control::{
          element: {
            reference: Some(save),
            text: "Queue two writes",
            focused: false,
            bounds: { x: 16, y: 16, width: 220, height: 40, },
          },
          kind: Button,
          clip: None,
        },
      ]
    },
    activate: reference => {
      if reference == save {
        if !writer.enqueue(1, "first") || !writer.enqueue(2, "second") {
          abort("serial write was not queued")
        }
      }
      None
    },
    edited: _ => None,
    resize: (_, _) => false,
    stop: () => {
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
  @window_host.run(
    @host_application.from_application(app),
    hidden=true,
    controller=Some(handle => {
      @async.with_timeout(5000, () => {
        assert_eq(
          (handle.operate)(save, ActivateControl, @semantics.revision(tree)),
          "",
        )
        while started.length() == 0 {
          @async.sleep(1)
        }
        assert_eq(started, [1])
        assert_eq(applied, [])
        assert_eq(writer.snapshot().active.unwrap().identity, 1)
        assert_eq(writer.snapshot().queued.length(), 1)
        release.val = true
        while applied.length() < 2 {
          @async.sleep(1)
        }
        assert_eq(started, [1, 2])
        assert_eq(applied, [1, 2])
        assert_true(writer.snapshot().active is None)
        assert_true(writer.snapshot().queued.is_empty())
        finished.val = true
        (handle.apply)(Close)
      })
    }),
  )
  assert_true(finished.val)
}
