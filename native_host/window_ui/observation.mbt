///|
pub(all) enum Injected {
  Close
  CompositionStart
  CompositionUpdate(String, Int?)
  CompositionAttributes(String, Int?, Bytes)
  CompositionCancel
  NavigateVertical(Bool, Bool)
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
  rendered_editor_caret : Int?
  rendered_query_caret : Int?
  preedit_attributes : Bytes
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
