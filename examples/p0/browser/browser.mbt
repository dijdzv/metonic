///|
let state : Ref[@scene.State] = { val: @scene.create(), }

///|
#export_name("init")
pub fn reset_state() -> Unit {
  state.val = @scene.create()
}

///|
#export_name("resize")
pub fn resize(width : Int, height : Int) -> Int {
  if @scene.resize(state.val, width, height) {
    1
  } else {
    0
  }
}

///|
#export_name("move_to")
pub fn move_to(x : Int, y : Int) -> Int {
  if @scene.move_to(state.val, x, y) {
    1
  } else {
    0
  }
}

///|
#export_name("activate")
pub fn activate() -> Unit {
  @scene.activate(state.val)
}

///|
#export_name("field")
pub fn field(index : Int) -> Int {
  @scene.field(state.val, index)
}
