///|
let application : Ref[@application.Model] = Ref(@application.create(1, 1))

///|
#export_name("init")
pub fn reset_state() -> Unit {
  editor_composition_end()
  ignore(@semantics.dispose(application.val.editor))
  ignore(application.val.stop())
  application.val = @application.create(1, 1)
}

///|
#export_name("task_begin")
pub fn task_begin() -> Int {
  application.val.begin_update()
}

///|
#export_name("task_complete")
pub fn task_complete(id : Int, value : Int) -> Int {
  if application.val.complete_movement(id, value) {
    1
  } else {
    0
  }
}

///|
#export_name("task_fail")
pub fn task_fail(id : Int, code : Int) -> Int {
  if @task_scope.fail(application.val.tasks, id, code) {
    1
  } else {
    0
  }
}

///|
#export_name("task_cancel")
pub fn task_cancel() -> Int {
  if application.val.cancel_update() {
    1
  } else {
    0
  }
}

///|
#export_name("task_dispose")
pub fn task_dispose() -> Int {
  if application.val.stop() {
    1
  } else {
    0
  }
}

///|
#export_name("task_field")
pub fn task_field(index : Int) -> Int {
  @task_scope.field(application.val.tasks, index)
}

///|
#export_name("resize")
pub fn resize(width : Int, height : Int) -> Int {
  if @scene.resize(application.val.scene, width, height) {
    1
  } else {
    0
  }
}

///|
#export_name("move_to")
pub fn move_to(x : Int, y : Int) -> Int {
  if @scene.move_to(application.val.scene, x, y) {
    1
  } else {
    0
  }
}

///|
#export_name("activate")
pub fn activate() -> Unit {
  @scene.activate(application.val.scene)
}

///|
#export_name("field")
pub fn field(index : Int) -> Int {
  @scene.field(application.val.scene, index)
}
