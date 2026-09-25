///|
async fn verify_publication() -> Unit {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let registry = @reactive_task.PublicationRegistry::new(root)
  let downstream_registry = @reactive_task.DownstreamRegistry::new(root)
  let source : @reactive_task.Source[String, Int] = @reactive_task.Source::new(
    root,
  )
  let cycle = @reactive_task.Cycle::new()
  let demand = @reactive.Signal::new(root, "item-1")
  let downstream_release = Ref(false)
  let downstream_cleanup = Ref(0)
  let published = registry.register(root, () => {
    (demand.get(), source.current(demand.get(), cycle))
  })
  let downstream = downstream_registry.register(
    root,
    () => source.current(demand.get(), cycle),
    async fn(value : Int) {
      defer {
        downstream_cleanup.val += 1
      }
      while !downstream_release.val {
        @async.sleep(1)
      }
      value * 2
    },
  )
  let downstream_published = registry.register(root, () => {
    (demand.get(), downstream.current())
  })
  let tree = @semantics.empty(928, 1)
  let switch = @semantics.add_button(tree, "Switch item").unwrap()
  let release = Ref(false)
  let app : @portable.Application = {
    title: "Publication boundary probe",
    editor: tree,
    default_input: None,
    initial_size: (480, 240),
    viewport: None,
    publications: Some(registry),
    downstreams: Some(downstream_registry),
    serials: None,
    components: None,
    connect_tasks: control => {
      if !source.connect(control) {
        abort("publication source was not connected")
      }
      if !downstream_registry.connect(control) {
        abort("downstream registry was not connected")
      }
    },
    initialize: () => {
      source.replace("item-1", cycle, false, () => {
        while !release.val {
          @async.sleep(1)
        }
        7
      })
    },
    view: () => {
      let label = match published.get() {
        None => "Not published"
        Some(state) => {
          let phase = match state.current {
            @reactive_task.CurrentPending(_) => "Pending"
            @reactive_task.CurrentReady(value, _) =>
              "Ready " + value.to_string()
            @reactive_task.CurrentBlocked(_) => "Blocked"
            _ => "Other"
          }
          state.demand + ": " + phase
        }
      }
      [
        @portable.Control::{
          element: {
            reference: None,
            text: label,
            focused: false,
            bounds: { x: 16, y: 16, width: 420, height: 40, },
          },
          kind: Text,
          clip: None,
        },
        @portable.Control::{
          element: {
            reference: None,
            text: match downstream_published.get() {
              Some(state) =>
                match state.current {
                  @reactive_task.CurrentReady(value, _) =>
                    "Downstream " + value.to_string()
                  @reactive_task.CurrentPending(_) => "Downstream pending"
                  @reactive_task.CurrentBlocked(_) => "Downstream blocked"
                  _ => "Downstream other"
                }
              None => "Downstream not published"
            },
            focused: false,
            bounds: { x: 220, y: 68, width: 240, height: 40, },
          },
          kind: Text,
          clip: None,
        },
        @portable.Control::{
          element: {
            reference: Some(switch),
            text: "Switch item",
            focused: false,
            bounds: { x: 16, y: 68, width: 180, height: 40, },
          },
          kind: Button,
          clip: None,
        },
      ]
    },
    activate: reference => {
      if reference == switch {
        demand.set(if demand.peek() == "item-1" { "item-2" } else { "item-1" })
      }
      None
    },
    edited: _ => None,
    resize: (_, _) => false,
    stop: () => {
      source.dispose()
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
        while published.get() is None ||
              !(published.get().unwrap().current
              is @reactive_task.CurrentPending(_)) {
          @async.sleep(1)
        }
        let pending = (handle.capture)(_ => ())
        release.val = true
        while !(published.get().unwrap().current
              is @reactive_task.CurrentReady(7, _)) {
          @async.sleep(1)
        }
        while !(downstream_published.get().unwrap().current
              is @reactive_task.CurrentPending(_)) {
          @async.sleep(1)
        }
        let child_pending = (handle.capture)(_ => ())
        assert_true(child_pending.pixels != pending.pixels)
        assert_eq(
          (handle.operate)(switch, ActivateControl, @semantics.revision(tree)),
          "",
        )
        assert_eq(published.get().unwrap().demand, "item-2")
        assert_true(
          published.get().unwrap().current is @reactive_task.CurrentBlocked(_),
        )
        assert_true(published.get().unwrap().previous is None)
        assert_true(
          downstream_published.get().unwrap().current
          is @reactive_task.CurrentBlocked(_),
        )
        assert_true(downstream_published.get().unwrap().previous is None)
        while downstream_cleanup.val == 0 {
          @async.sleep(1)
        }
        let switched = (handle.capture)(_ => ())
        assert_true(switched.pixels != child_pending.pixels)
        assert_eq(
          (handle.operate)(switch, ActivateControl, @semantics.revision(tree)),
          "",
        )
        assert_true(
          downstream_published.get().unwrap().current
          is @reactive_task.CurrentPending(_),
        )
        downstream_release.val = true
        while !(downstream_published.get().unwrap().current
              is @reactive_task.CurrentReady(14, _)) {
          @async.sleep(1)
        }
        let ready = (handle.capture)(_ => ())
        assert_true(ready.pixels != switched.pixels)
        (handle.apply)(Close)
        finished.val = true
      })
    }),
  )
  assert_true(finished.val)
}
