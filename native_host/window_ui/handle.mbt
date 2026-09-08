///|
pub(all) enum Action {
  Move(Int, Int)
  Activate
  Insert(String)
  Backspace
  StartUpdate
  LoadUser(String)
  CancelUpdate
  Close
}

///|
pub struct Snapshot {
  x : Int
  y : Int
  width : Int
  height : Int
  semantic_revision : Int
  text : String
  selection_start : Int
  selection_end : Int
  selection_anchor : Int
  caret : Int
  frames : Int
  task_status : Int
  rpc_result : String
  composing : Bool
  preedit : String
  preedit_cursor : Int?
  ime_requested_x : Int?
  ime_requested_y : Int?
  closed : Bool
}

///|
pub struct Handle {
  inspect : () -> Snapshot
  apply : async (Action) -> Unit
  edit : async (String?, Int?) -> String
  select : async (Int, Int, Int?) -> String
  capture : async () -> Captured
}

///|
pub struct Captured {
  pixels : Bytes
  width : Int
  height : Int
  frame : Int
}

///|
fn App::handle(self : App) -> Handle {
  {
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
    capture: () => {
      require(!self.closed, "window closed")
      let result : Ref[Result[Captured, Error]?] = Ref(None)
      self.events.put(Development(Capture(result)))
      while result.val is None && !self.closed {
        @async.sleep(1)
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
    inspect: () => {
      let node = @semantics.snapshot(self.model.editor)[1]
      {
        x: @scene.field(self.model.scene, 0),
        y: @scene.field(self.model.scene, 1),
        width: @scene.field(self.model.scene, 6),
        height: @scene.field(self.model.scene, 7),
        semantic_revision: @semantics.revision(self.model.editor),
        text: node.value,
        selection_start: node.selection_start,
        selection_end: node.selection_end,
        selection_anchor: node.selection_anchor,
        caret: @semantics.caret(node),
        frames: self.diagnostics.frames,
        task_status: self.model.task_field(0),
        rpc_result: self.model.result,
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
      }
    },
    apply: action => {
      require(!self.closed, "window closed")
      let event = match action {
        Move(x, y) => Input(@scene.Action::Move(x, y))
        Activate => Input(@scene.Action::Activate)
        Insert(text) => Commit(text)
        Backspace => Event::Backspace
        StartUpdate => Event::StartUpdate
        LoadUser(id) => Event::LoadUser(id)
        CancelUpdate => Event::CancelUpdate
        Close => Event::Close
      }
      let applied = Ref(false)
      self.events.put(event)
      self.events.put(Development(Barrier(applied)))
      while !applied.val && !self.closed {
        @async.sleep(1)
      }
    },
  }
}
