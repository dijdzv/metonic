///|
/// Contract metadata only. I/O/E are phantom parameters, not runtime handlers.
pub struct Procedure[I, O, E] {
  id : String
  // Always None; retains type identity without storing executable handlers.
  type_witness : (I, O, E)?
}

///|
pub fn[I, O, E] Procedure::new(id : String) -> Procedure[I, O, E] {
  { id, type_witness: None, }
}

///|
/// An in-process binding for the type-boundary experiment, not a transport.
pub struct Binding[I, O, E] {
  procedure : Procedure[I, O, E]
  handler : (I) -> Result[O, E]
}

///|
pub fn[I, O, E] bind(
  procedure : Procedure[I, O, E],
  handler : (I) -> Result[O, E],
) -> Binding[I, O, E] {
  { procedure, handler, }
}

///|
pub fn[I, O, E] Binding::call(
  self : Binding[I, O, E],
  input : I,
) -> Result[O, E] {
  (self.handler)(input)
}
