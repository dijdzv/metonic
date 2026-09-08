///|
pub struct Model {
  scene : @scene.State
  editor : @semantics.Tree
  request_button : @semantics.NodeRef
  start_button : @semantics.NodeRef
  cancel_button : @semantics.NodeRef
  tasks : @task_scope.Scope
  mut result : String
  mut result_utf8 : Bytes
}

///|
pub fn create(session : Int, window : Int) -> Model {
  let editor = @semantics.create(session, window)
  let request_button = @semantics.add_button(editor, "Load user").unwrap()
  let start_button = @semantics.add_button(editor, "Move after delay").unwrap()
  let cancel_button = @semantics.add_button(editor, "Cancel").unwrap()
  {
    scene: @scene.create(),
    editor,
    request_button,
    start_button,
    cancel_button,
    tasks: @task_scope.create(),
    result: "",
    result_utf8: b"",
  }
}

///|
pub fn Model::begin_update(self : Model) -> Int {
  @task_scope.begin(self.tasks)
}

///|
pub fn Model::task_field(self : Model, index : Int) -> Int {
  @task_scope.field(self.tasks, index)
}

///|
pub fn Model::cancel_update(self : Model) -> Bool {
  @task_scope.cancel(self.tasks)
}

///|
pub fn Model::complete_movement(self : Model, id : Int, x : Int) -> Bool {
  if !@task_scope.complete(self.tasks, id, x) {
    return false
  }
  ignore(@scene.move_to(self.scene, x, @scene.field(self.scene, 1)))
  true
}

///|
pub fn Model::complete_user(
  self : Model,
  id : Int,
  response : Result[String, String],
) -> Bool {
  let text = match response {
    Ok(name) => {
      guard @task_scope.complete(self.tasks, id, 0) else { return false }
      "\n" + name
    }
    Err(error) => {
      guard @task_scope.fail(self.tasks, id, 1) else { return false }
      "\nRPC: " + error
    }
  }
  self.result = text
  self.result_utf8 = @utf8.encode(text)
  true
}

///|
pub fn Model::stop(self : Model) -> Bool {
  // Keep the final editor/scene snapshot available to host shutdown observers.
  @task_scope.dispose(self.tasks)
}
