///|
#export_name("scene_pointer")
pub fn scene_pointer(x : Int, y : Int) -> Int {
  if x >= field(0) &&
    x <= field(0) + field(2) &&
    y >= field(1) &&
    y <= field(1) + field(3) {
    activate()
    1
  } else {
    move_to(x, y)
  }
}

///|
#export_name("scene_key")
pub fn scene_key(key : String) -> Int {
  match key {
    "ArrowLeft" => move_to(field(0) - 10, field(1))
    "ArrowRight" => move_to(field(0) + 10, field(1))
    "ArrowUp" => move_to(field(0), field(1) - 10)
    "ArrowDown" => move_to(field(0), field(1) + 10)
    " " | "Enter" => {
      activate()
      1
    }
    _ => -1
  }
}
