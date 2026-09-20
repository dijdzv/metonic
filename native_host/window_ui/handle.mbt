///|
pub(all) enum Action {
  Move(Int, Int)
  Resize(Int, Int)
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
  ime_events : Array[Json]
  raw_ime_events : Array[Json]
  raw_ime_dropped : Int64
  ime_dropped : Int64
  input : InputObservation
  view : @application.View
  x : Int
  y : Int
  width : Int
  height : Int
  semantic_revision : Int
  scene_revision : Int
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
  retained_frame_id : () -> Int64
  capture_retained : async (Int64) -> @gpu.RetainedCapture
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
