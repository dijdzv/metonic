///|
extern "C" fn native_navigate(parent : UInt64, direction : Int) -> UInt64 = "metonic_uia_navigate"

///|
extern "C" fn native_focused_node() -> UInt64 = "metonic_uia_focused_node"

///|
extern "C" fn native_selected_range(provider : UInt64) -> UInt64 = "metonic_uia_selected_range"

///|
pub fn navigate(parent : UInt64, direction : Int) -> UInt64 {
  native_navigate(parent, direction)
}

///|
pub fn focused_node() -> UInt64 {
  native_focused_node()
}

///|
pub fn selected_range(provider : UInt64) -> UInt64 {
  native_selected_range(provider)
}
