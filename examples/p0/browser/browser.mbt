///|
let state : Ref[@scene.State] = { val: @scene.create(), }

///|
#export_name("init")
pub fn reset_state() -> Unit {
  reset_editor()
  ignore(@task_scope.dispose(taskScope.val))
  taskScope.val = @task_scope.create()
  state.val = @scene.create()
  rpc_result.val = b""
}

///|
let taskScope : Ref[@task_scope.Scope] = { val: @task_scope.create(), }

///|
#export_name("task_begin")
pub fn task_begin() -> Int {
  @task_scope.begin(taskScope.val)
}

///|
#export_name("task_complete")
pub fn task_complete(id : Int, value : Int) -> Int {
  if @task_scope.complete(taskScope.val, id, value) {
    ignore(@scene.move_to(state.val, value, @scene.field(state.val, 1)))
    1
  } else {
    0
  }
}

///|
#export_name("task_fail")
pub fn task_fail(id : Int, code : Int) -> Int {
  if @task_scope.fail(taskScope.val, id, code) {
    1
  } else {
    0
  }
}

///|
#export_name("task_cancel")
pub fn task_cancel() -> Int {
  if @task_scope.cancel(taskScope.val) {
    1
  } else {
    0
  }
}

///|
#export_name("task_dispose")
pub fn task_dispose() -> Int {
  if @task_scope.dispose(taskScope.val) {
    1
  } else {
    0
  }
}

///|
#export_name("task_field")
pub fn task_field(index : Int) -> Int {
  @task_scope.field(taskScope.val, index)
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
