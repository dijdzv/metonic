///|
pub(all) enum Injected {
  Close
  CompositionStart
  CompositionUpdate(String, Int?)
  CompositionAttributes(String, Int?, Bytes)
  CompositionCancel
  NavigateVertical(Bool, Bool)
  AccessibilityValue(Int, String)
  AccessibilitySelection(UInt64, UInt64, UInt64, UInt64)
  Result(@task.Completion)
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
  capture_srgb : Bool
  ime_position : (Int, Int)?
  accessibility_runs : Array[UInt64]
  preedit_cursor : Int
  preedit_attributes : Bytes
  composing : Bool
  rejected_updates : Int
  scroll_x : (@semantics.NodeRef) -> Int
  caret_position : (@semantics.NodeRef) -> (Int, Int)?
  rendered_text : (@semantics.NodeRef) -> String?
  rendered_caret : (@semantics.NodeRef) -> Int?
  resize : (Int, Int) -> Unit
  select : (@semantics.NodeRef, Int, Int) -> String
  set_text : (@semantics.NodeRef, String) -> String
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
    capture_srgb: self.renderer
    .map(renderer => {
      renderer.format.to_u32() == @wgpu.TEXTURE_FORMAT_BGRA8_UNORM_SRGB ||
      renderer.format.to_u32() == @wgpu.TEXTURE_FORMAT_RGBA8_UNORM_SRGB
    })
    .unwrap_or(false),
    ime_position: self.window.map(window => {
      (
        window.ime_cursor_area_position().x(),
        window.ime_cursor_area_position().y(),
      )
    }),
    accessibility_runs: self.accessibility
    .map(bridge => bridge.fragment_ids())
    .unwrap_or([]),
    preedit_cursor: self.preedit_cursor,
    preedit_attributes: self.preedit_attributes,
    composing: self.composition is Some(_),
    rejected_updates: self.diagnostics.rejected_updates,
    scroll_x: reference => self.input_layouts.scroll_x(reference),
    caret_position: reference => {
      guard self.input_layouts.engine(reference) is Some(engine) else {
        return None
      }
      guard @semantics.node(self.host.editor, reference) is Ok(node) else {
        return None
      }
      let caret = if self.composition is Some(_) &&
        self.input_node().reference == reference {
        node.selection_start +
        @ime_presentation.display_cursor(
          self.preedit,
          self.preedit_cursor,
          self.preedit_attributes,
        )
      } else {
        @semantics.caret(node)
      }
      @raster.caret_position(engine, caret)
    },
    rendered_text: reference => {
      self.presenter.bind(presenter => presenter.input_text(reference))
    },
    rendered_caret: reference => {
      self.presenter.bind(presenter => presenter.active_caret(reference))
    },
    resize: (width, height) => {
      ignore(
        self.window
        .unwrap()
        .request_inner_size(@dpi.PhysicalSize(width, height).into_size()),
      )
    },
    select: (reference, anchor, caret) => {
      @semantics.set_selection_directed(
        self.host.editor,
        reference,
        anchor,
        caret,
      )
    },
    set_text: (reference, text) => {
      @semantics.set_text(self.host.editor, reference, text)
    },
    draw: () => self.draw(),
    capture: () => self.renderer.unwrap().capture_frame(),
    inject: action => {
      self.queue(
        match action {
          Close => Close
          CompositionStart => CompositionStart
          CompositionUpdate(text, cursor) =>
            CompositionUpdate(text, cursor, b"")
          CompositionAttributes(text, cursor, attributes) =>
            CompositionUpdate(text, cursor, attributes)
          CompositionCancel => CompositionCancel
          NavigateVertical(down, extend_selection) =>
            NavigateVertical(down, extend_selection)
          AccessibilityValue(target, text) =>
            Accessibility(@accessibility.SetValue(target, text))
          AccessibilitySelection(a, b, c, d) =>
            Accessibility(@accessibility.Select(a, b, c, d))
          Result(result) => ApplicationResult(result)
        },
      )
    },
  }
}
