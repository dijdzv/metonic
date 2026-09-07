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
  frames : Int
  task_status : Int
  rpc_result : String
  closed : Bool
}

///|
pub struct Handle {
  inspect : () -> Snapshot
  apply : async (Action) -> Unit
  edit : async (String?, Int?) -> String
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
    capture: () => {
      require(!self.closed, "window closed")
      let result : Ref[Result[Captured, Error]?] = Ref(None)
      self.events.put(Capture(result))
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
      self.events.put(Edit(text, expected, result))
      while result.val is None && !self.closed {
        @async.sleep(1)
      }
      result.val.unwrap_or("closed")
    },
    inspect: () => {
      let node = @semantics.snapshot(self.editor)[1]
      {
        x: @scene.field(self.state, 0),
        y: @scene.field(self.state, 1),
        width: @scene.field(self.state, 6),
        height: @scene.field(self.state, 7),
        semantic_revision: @semantics.revision(self.editor),
        text: node.value,
        selection_start: node.selection_start,
        selection_end: node.selection_end,
        frames: self.frames,
        task_status: @task_scope.field(self.scope, 0),
        rpc_result: self.rpc_result,
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
      self.events.put(Barrier(applied))
      while !applied.val && !self.closed {
        @async.sleep(1)
      }
    },
  }
}
