///|
pub using @window_host {type InputObservation, type Lifecycle}

///|
fn snapshot(
  model : @application.Model,
  state : @window_host.Snapshot,
) -> Snapshot {
  {
    ime_events: state.ime_events,
    raw_ime_events: state.raw_ime_events,
    raw_ime_dropped: state.raw_ime_dropped,
    ime_dropped: state.ime_dropped,
    input: state.input,
    width: state.width,
    height: state.height,
    semantic_revision: state.semantic_revision,
    text: state.text,
    selection_start: state.selection_start,
    selection_end: state.selection_end,
    selection_anchor: state.selection_anchor,
    caret: state.caret,
    frames: state.frames,
    composing: state.composing,
    preedit: state.preedit,
    preedit_cursor: state.preedit_cursor,
    ime_requested_x: state.ime_requested_x,
    ime_requested_y: state.ime_requested_y,
    closed: state.closed,
    view: model.view(),
    x: @p0_application.scene_field(model, 0),
    y: @p0_application.scene_field(model, 1),
    scene_revision: @p0_application.scene_field(model, 5),
    task_status: model.task_field(0),
    rpc_result: model.result,
  }
}

///|
fn handle(model : @application.Model, host : @window_host.Handle) -> Handle {
  {
    inspect: () => snapshot(model, (host.inspect)()),
    apply: action => {
      (host.apply)(
        match action {
          Move(x, y) => @window_host.Move(x, y)
          Resize(w, h) => @window_host.Resize(w, h)
          Activate => @window_host.Activate
          Insert(text) => @window_host.Insert(text)
          Backspace => @window_host.Backspace
          StartUpdate =>
            @window_host.Task(
              @p0_application.movement(model),
              @host_application.PointerIdle,
            )
          LoadUser(id) =>
            @window_host.Task(
              @p0_application.user(model, id),
              @host_application.CommittedInput,
            )
          CancelUpdate =>
            @window_host.Task(
              @p0_application.cancel(model),
              @host_application.Always,
            )
          Close => @window_host.Close
        },
      )
    },
    edit: host.edit,
    select: host.select,
    capture: () => {
      let state : Ref[Snapshot?] = Ref(None)
      let captured = (host.capture)(value => {
        state.val = Some(snapshot(model, value))
      })
      {
        state: state.val.unwrap(),
        pixels: captured.pixels,
        width: captured.width,
        height: captured.height,
        frame: captured.frame,
      }
    },
    retained_frame_id: host.retained_frame_id,
    capture_retained: host.capture_retained,
    wait_display: host.wait_display,
    wait_semantic: host.wait_semantic,
  }
}

///|
fn observation(
  model : @application.Model,
  state : @window_host.Observation,
) -> Observation {
  {
    ime_events: state.ime_events,
    raw_ime_events: state.raw_ime_events,
    raw_ime_dropped: state.raw_ime_dropped,
    ime_dropped: state.ime_dropped,
    input: state.input,
    closed_queue_empty: state.closed_queue_empty,
    frames: state.frames,
    pending_initialization: state.pending_initialization,
    has_renderer: state.has_renderer,
    hwnd: state.hwnd,
    capture_srgb: state.capture_srgb,
    ime_position: state.ime_position,
    accessibility_runs: state.accessibility_runs,
    preedit_cursor: state.preedit_cursor,
    preedit_attributes: state.preedit_attributes,
    composing: state.composing,
    rejected_updates: state.rejected_updates,
    resize: state.resize,
    draw: state.draw,
    capture: state.capture,
    scene: index => @p0_application.scene_field(model, index),
    task: index => model.task_field(index),
    editor: @semantics.node(model.editor, model.editor_input).unwrap(),
    query: @semantics.node(model.editor, model.query_input).unwrap(),
    rpc_result: model.result,
    query_scroll: (state.scroll_x)(model.query_input),
    query_caret_position: (state.caret_position)(model.query_input),
    request_focused: model.request_focused(),
    rendered_text: (state.rendered_text)(model.editor_input),
    rendered_editor_caret: (state.rendered_caret)(model.editor_input),
    rendered_query_caret: (state.rendered_caret)(model.query_input),
    select: (start, end) => {
      @semantics.set_selection(model.editor, model.editor_input, start, end)
    },
    select_query: (anchor, caret) => {
      (state.select)(model.query_input, anchor, caret)
    },
    set_text: text => (state.set_text)(model.editor_input, text),
    inject: action => {
      (state.inject)(
        match action {
          Close => @window_host.Injected::Close
          CompositionStart => @window_host.Injected::CompositionStart
          CompositionUpdate(text, cursor) =>
            @window_host.Injected::CompositionUpdate(text, cursor)
          CompositionAttributes(text, cursor, attrs) =>
            @window_host.Injected::CompositionAttributes(text, cursor, attrs)
          CompositionCancel => @window_host.Injected::CompositionCancel
          NavigateVertical(down, extend_selection) =>
            @window_host.Injected::NavigateVertical(down, extend_selection)
          AccessibilityValue(text) =>
            @window_host.Injected::AccessibilityValue(
              model.editor_input.id,
              text,
            )
          AccessibilitySelection(a, b, c, d) =>
            @window_host.Injected::AccessibilitySelection(a, b, c, d)
          Updated(id, value) =>
            @window_host.Injected::Result(
              @p0_application.movement_result(model, id, value),
            )
        },
      )
    },
  }
}

///|
pub async fn run(
  display_feedback? : ((@wgpu.Surface) -> @gpu.DisplayObservation)? = None,
  observer? : (async (Observation) -> Unit)? = None,
  completed? : ((Observation) -> Unit raise Error)? = None,
  lifecycle? : ((Lifecycle, Observation) -> Bool raise Error)? = None,
  controller? : (async (Handle) -> Unit)? = None,
  hidden? : Bool = false,
  report? : (String) -> Unit = println,
) -> Unit {
  let model = @application.create(1, 1)
  @window_host.run(
    @p0_application.create(model),
    display_feedback~,
    observer=observer.map(callback => {
      state => callback(observation(model, state))
    }),
    completed=completed.map(callback => {
      state => callback(observation(model, state))
    }),
    lifecycle=lifecycle.map(callback => {
      (phase, state) => callback(phase, observation(model, state))
    }),
    controller=controller.map(callback => host => callback(handle(model, host))),
    hidden~,
    report~,
  )
}
