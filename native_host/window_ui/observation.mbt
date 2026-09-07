///|
pub(all) enum Injected {
  CompositionStart
  CompositionUpdate(String, Int?)
  CompositionCancel
  Updated(Int, Int)
}

///|
pub struct Observation {
  frames : Int
  pending_initialization : Int
  has_renderer : Bool
  hwnd : UInt64
  scene : (Int) -> Int
  task : (Int) -> Int
  editor : @semantics.Node
  rendered_text : String?
  preedit_cursor : Int
  composing : Bool
  rejected_updates : Int
  resize : (Int, Int) -> Unit
  select : (Int, Int) -> String
  set_text : (String) -> String
  draw : () -> Unit raise Error
  capture : async () -> Bytes
  inject : (Injected) -> Unit
}

///|
fn App::observation(self : App) -> Observation {
  {
    frames: self.diagnostics.frames,
    pending_initialization: self.owner.pending_count(),
    has_renderer: self.renderer is Some(_),
    hwnd: self.hwnd,
    scene: index => @scene.field(self.state, index),
    task: index => @task_scope.field(self.scope, index),
    editor: @semantics.snapshot(self.editor)[1],
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
        self.editor,
        @semantics.snapshot(self.editor)[1].reference,
        start,
        end,
      )
    },
    set_text: text => {
      @semantics.set_text(
        self.editor,
        @semantics.snapshot(self.editor)[1].reference,
        text,
      )
    },
    draw: () => self.draw(),
    capture: () => self.renderer.unwrap().capture_frame(),
    inject: action => {
      self.queue(
        match action {
          CompositionStart => CompositionStart
          CompositionUpdate(text, cursor) => CompositionUpdate(text, cursor)
          CompositionCancel => CompositionCancel
          Updated(id, value) => Updated(id, value)
        },
      )
    },
  }
}
