///|
pub(all) enum Action {
  Move(Int, Int)
  Resize(Int, Int)
  Activate
  Insert(String)
  Backspace
  Task(@task.Request, @host_application.TaskGate)
  Close
}

///|
pub(all) enum ControlAction {
  InsertText(String)
  DeleteBackward
  SelectRange(Int, Int)
  ActivateControl
}

///|
pub struct Snapshot {
  default_input : @semantics.NodeRef?
  controls : Array[@semantics.Node]
  ime_events : Array[Json]
  raw_ime_events : Array[Json]
  raw_ime_dropped : Int64
  ime_dropped : Int64
  input : InputObservation
  width : Int
  height : Int
  semantic_revision : Int
  text : String
  selection_start : Int
  selection_end : Int
  selection_anchor : Int
  caret : Int
  frames : Int
  composing : Bool
  preedit : String
  preedit_cursor : Int?
  ime_requested_x : Int?
  ime_requested_y : Int?
  closed : Bool
  diagnostics : Json?
}

///|
pub struct Handle {
  operate : async (@semantics.NodeRef, ControlAction, Int) -> String
  inspect : () -> Snapshot
  apply : async (Action) -> Unit
  edit : async (String?, Int?) -> String
  select : async (Int, Int, Int?) -> String
  capture : async ((Snapshot) -> Unit) -> Captured
  retained_frame_id : () -> Int64
  capture_retained : async (Int64) -> @gpu.RetainedCapture
  gpu_resources : () -> @gpu.SurfaceGpuResources?
  wait_display : async (Int64, Int) -> String
  wait_semantic : async (Int, Int) -> String
}

///|
pub struct Captured {
  state : Snapshot
  pixels : Bytes
  width : Int
  height : Int
  frame : Int
}

///|
fn App::handle(self : App) -> Handle {
  {
    operate: (target, action, revision) => {
      if self.closed {
        return "closed"
      }
      let result : Ref[String?] = Ref(None)
      self.events.put(Development(Operate(target, action, revision, result)))
      defer self.diagnostics.changed.broadcast()
      while result.val is None && !self.closed {
        self.diagnostics.changed.wait()
        if @async.is_being_cancelled() {
          @async.pause()
        }
      }
      result.val.unwrap_or("closed")
    },
    wait_display: (id, timeout_ms) => {
      if id <= 0L || timeout_ms < 1 || timeout_ms > 60000 {
        return "invalid_wait"
      }
      defer self.diagnostics.changed.broadcast()
      @async.with_timeout(timeout_ms, () => {
        while !self.closed {
          let result : Ref[@gpu.DisplayStatus?] = Ref(None)
          self.events.put(Development(DisplayStatus(id, result)))
          while result.val is None && !self.closed {
            self.diagnostics.changed.wait()
            if @async.is_being_cancelled() {
              @async.pause()
            }
          }
          if self.closed {
            return "closed"
          }
          match result.val.unwrap() {
            @gpu.DisplayStatus::Confirmed => return ""
            @gpu.DisplayStatus::Pending => @async.sleep(16)
            @gpu.DisplayStatus::Unavailable => return "display_unavailable"
            @gpu.DisplayStatus::Stale => return "stale_display_epoch"
            @gpu.DisplayStatus::InvalidFrame => return "invalid_frame"
            @gpu.DisplayStatus::NotSubmitted => return "frame_not_submitted"
            @gpu.DisplayStatus::Evicted => return "frame_evicted"
            @gpu.DisplayStatus::Closed => return "closed"
          }
        }
        "closed"
      }) catch {
        @async.TimeoutError => "timeout"
        error => raise error
      }
    },
    retained_frame_id: () => {
      self.renderer.map(renderer => renderer.retained_frame_id()).unwrap_or(0L)
    },
    gpu_resources: () => self.renderer.map(renderer => renderer.gpu_resources()),
    capture_retained: id => {
      require(!self.closed, "window closed")
      let result : Ref[Result[@gpu.RetainedCapture, Error]?] = Ref(None)
      defer self.diagnostics.changed.broadcast()
      self.events.put(Development(CaptureRetained(id, result)))
      while result.val is None && !self.closed {
        self.diagnostics.changed.wait()
        // A delivered notification must not turn cancellation into success.
        if @async.is_being_cancelled() {
          @async.pause()
        }
      }
      match result.val {
        Some(Ok(value)) => value
        Some(Err(error)) => raise error
        None => raise WindowFailure::Failure("window closed")
      }
    },
    wait_semantic: (revision, timeout_ms) => {
      if revision < 0 || timeout_ms < 1 || timeout_ms > 60000 {
        return "invalid_wait"
      }
      // WhyNot: a submitted-frame count cannot certify semantic or display completion.
      // Broadcast also removes canceled waiters retained by Cond until its next signal.
      defer self.diagnostics.changed.broadcast()
      @async.with_timeout(timeout_ms, () => {
        while !self.closed && @semantics.revision(self.host.editor) < revision {
          self.diagnostics.changed.wait()
          // WhyNot: Cond preserves a delivered signal during cancellation;
          // a read-only wait must still honor cancellation before returning.
          if @async.is_being_cancelled() {
            @async.pause()
          }
        }
        if self.closed {
          "closed"
        } else {
          ""
        }
      }) catch {
        @async.TimeoutError => "timeout"
        error => raise error
      }
    },
    select: (start, end, expected) => {
      if self.closed {
        return "closed"
      }
      let result : Ref[String?] = Ref(None)
      self.events.put(Development(Select(start, end, expected, result)))
      while result.val is None && !self.closed {
        @async.sleep(1)
      }
      result.val.unwrap_or("closed")
    },
    capture: observe => {
      require(!self.closed, "window closed")
      let result : Ref[Result[Captured, Error]?] = Ref(None)
      defer self.diagnostics.changed.broadcast()
      self.events.put(Development(Capture(result, observe)))
      while result.val is None && !self.closed {
        self.diagnostics.changed.wait()
        if @async.is_being_cancelled() {
          @async.pause()
        }
      }
      match result.val {
        Some(Ok(value)) => value
        Some(Err(error)) => raise error
        None => raise WindowFailure::Failure("window closed")
      }
    },
    edit: (text, expected) => {
      if self.closed {
        return "closed"
      }
      let result : Ref[String?] = Ref(None)
      self.events.put(Development(Edit(text, expected, result)))
      while result.val is None && !self.closed {
        @async.sleep(1)
      }
      result.val.unwrap_or("closed")
    },
    inspect: () => self.snapshot(),
    apply: action => self.apply_action(action),
  }
}

///|
fn App::snapshot(self : App) -> Snapshot {
  let node = self.default_node()
  {
    default_input: node.map(node => node.reference),
    controls: @semantics.snapshot(self.host.editor),
    input: self.diagnostics.input,
    ime_events: self.diagnostics.ime_events.map(value => value),
    raw_ime_events: self.raw_ime_events(),
    raw_ime_dropped: self.raw_ime_dropped(),
    ime_dropped: self.diagnostics.ime_dropped,
    width: (self.host.view)().accessibility.width,
    height: (self.host.view)().accessibility.height,
    semantic_revision: @semantics.revision(self.host.editor),
    text: node.map(node => node.value).unwrap_or(""),
    selection_start: node.map(node => node.selection_start).unwrap_or(0),
    selection_end: node.map(node => node.selection_end).unwrap_or(0),
    selection_anchor: node.map(node => node.selection_anchor).unwrap_or(0),
    caret: node.map(node => @semantics.caret(node)).unwrap_or(0),
    frames: self.diagnostics.frames,
    composing: self.composition is Some(_),
    preedit: self.preedit,
    preedit_cursor: if self.composition is Some(_) {
      Some(self.preedit_cursor)
    } else {
      None
    },
    ime_requested_x: self.window.map(window => {
      window.ime_cursor_area_position().x()
    }),
    ime_requested_y: self.window.map(window => {
      window.ime_cursor_area_position().y()
    }),
    closed: self.closed,
    diagnostics: self.hooks.trace().map(registry => registry.snapshot_json()),
  }
}

///|
async fn App::apply_action(self : App, action : Action) -> Unit {
  require(!self.closed, "window closed")
  let prepared = Ref(true)
  let event = match action {
    Resize(width, height) => {
      require(
        width >= 1 && width <= 2048 && height >= 1 && height <= 2048,
        "invalid resize dimensions",
      )
      ignore(
        self.window
        .unwrap()
        .request_inner_size(@dpi.PhysicalSize(width, height).into_size()),
      )
      return
    }
    Move(x, y) => Input(Move(x, y))
    Activate => Input(Activate)
    Insert(text) => Commit(text)
    Backspace => Event::Backspace
    Task(request, gate) => {
      prepared.val = false
      ApplicationTask(request, gate, () => prepared.val = true)
    }
    Close => Event::Close
  }
  let applied = Ref(false)
  self.events.put(event)
  while !prepared.val && !self.closed {
    @async.sleep(1)
  }
  guard !self.closed else { return }
  self.events.put(Development(Barrier(applied)))
  while !applied.val && !self.closed {
    @async.sleep(1)
  }
}
