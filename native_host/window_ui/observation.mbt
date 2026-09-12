///|
pub(all) enum Injected {
  Close
  CompositionStart
  CompositionUpdate(String, Int?)
  CompositionCancel
  AccessibilityValue(String)
  AccessibilitySelection(UInt64, UInt64, UInt64, UInt64)
  Updated(Int, Int)
}

///|
pub struct Observation {
  ime_events : Array[Json]
  raw_ime_events : Array[Json]
  raw_ime_dropped : Int64
  ime_dropped : Int64
  input : InputObservation
  closed_queue_empty : Bool
  frames : Int
  pending_initialization : Int
  has_renderer : Bool
  hwnd : UInt64
  scene : (Int) -> Int
  task : (Int) -> Int
  editor : @semantics.Node
  query : @semantics.Node
  rpc_result : String
  query_scroll : Int
  capture_srgb : Bool
  query_caret_position : (Int, Int)?
  ime_position : (Int, Int)?
  request_focused : Bool
  accessibility_runs : Array[UInt64]
  rendered_text : String?
  preedit_cursor : Int
  composing : Bool
  rejected_updates : Int
  resize : (Int, Int) -> Unit
  select : (Int, Int) -> String
  select_query : (Int, Int) -> String
  set_text : (String) -> String
  draw : () -> Unit raise Error
  capture : async () -> Bytes
  inject : (Injected) -> Unit
}

///|
fn App::observation(self : App) -> Observation {
  {
    ime_events: self.diagnostics.ime_events.map(value => value),
    raw_ime_events: self.raw_ime_events(),
    raw_ime_dropped: self.raw_ime_dropped(),
    ime_dropped: self.diagnostics.ime_dropped,
    input: self.diagnostics.input,
    closed_queue_empty: if self.closed {
      try {
        ignore(self.events.try_get())
        false
      } catch {
        @aqueue.QueueAlreadyClosed => true
        _ => false
      }
    } else {
      false
    },
    frames: self.diagnostics.frames,
    pending_initialization: self.owner.pending_count(),
    has_renderer: self.renderer is Some(_),
    hwnd: self.hwnd,
    scene: index => @scene.field(self.model.scene, index),
    task: index => self.model.task_field(index),
    editor: @semantics.snapshot(self.model.editor)[1],
    query: @semantics.snapshot(self.model.editor)[5],
    rpc_result: self.model.result,
    query_scroll: self.query_scroll,
    capture_srgb: self.renderer
    .map(renderer => {
      renderer.format.to_u32() == @wgpu.TEXTURE_FORMAT_BGRA8_UNORM_SRGB ||
      renderer.format.to_u32() == @wgpu.TEXTURE_FORMAT_RGBA8_UNORM_SRGB
    })
    .unwrap_or(false),
    query_caret_position: self.query_raster
    .map(engine => {
      @raster.caret_position(
        engine,
        if self.composition is Some(_) &&
          self.input_node().reference == self.model.query_input {
          self.input_node().selection_start + self.preedit_cursor
        } else {
          @semantics.caret(@semantics.snapshot(self.model.editor)[5])
        },
      )
    })
    .bind(value => value),
    ime_position: self.window.map(window => {
      (
        window.ime_cursor_area_position().x(),
        window.ime_cursor_area_position().y(),
      )
    }),
    request_focused: self.model.request_focused(),
    accessibility_runs: self.accessibility
    .map(bridge => bridge.fragments.map(fragment => fragment.id))
    .unwrap_or([]),
    rendered_text: self.rendered_text,
    preedit_cursor: self.preedit_cursor,
    composing: self.composition is Some(_),
    rejected_updates: self.diagnostics.rejected_updates,
    resize: (width, height) => {
      ignore(
        self.window
        .unwrap()
        .request_inner_size(@dpi.PhysicalSize(width, height).into_size()),
      )
    },
    select: (start, end) => {
      @semantics.set_selection(
        self.model.editor,
        @semantics.snapshot(self.model.editor)[1].reference,
        start,
        end,
      )
    },
    select_query: (anchor, caret) => {
      @semantics.set_selection_directed(
        self.model.editor,
        self.model.query_input,
        anchor,
        caret,
      )
    },
    set_text: text => {
      @semantics.set_text(
        self.model.editor,
        @semantics.snapshot(self.model.editor)[1].reference,
        text,
      )
    },
    draw: () => self.draw(),
    capture: () => self.renderer.unwrap().capture_frame(),
    inject: action => {
      self.queue(
        match action {
          Close => Close
          CompositionStart => CompositionStart
          CompositionUpdate(text, cursor) => CompositionUpdate(text, cursor)
          CompositionCancel => CompositionCancel
          AccessibilityValue(text) =>
            Accessibility(@accessibility.SetValue(2, text))
          AccessibilitySelection(
            anchor_node,
            anchor_index,
            focus_node,
            focus_index
          ) =>
            Accessibility(
              @accessibility.Select(
                anchor_node, anchor_index, focus_node, focus_index,
              ),
            )
          Updated(id, value) => Updated(id, value)
        },
      )
    },
  }
}
