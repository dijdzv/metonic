///|
pub struct Scope {
  mut disposed : Bool
  mut next_id : Int
  mut current_id : Int
  mut status : Int
  mut value : Int
  mut error_code : Int
  mut revision : Int
}

///|
pub fn create() -> Scope {
  {
    disposed: false,
    next_id: 1,
    current_id: 0,
    status: 0,
    value: 0,
    error_code: 0,
    revision: 0,
  }
}

///|
pub fn begin(scope : Scope) -> Int {
  if scope.disposed || scope.next_id == 2147483647 {
    -1
  } else {
    let id = scope.next_id
    scope.next_id += 1
    scope.current_id = id
    scope.status = 1
    scope.error_code = 0
    scope.revision += 1
    id
  }
}

///|
pub fn complete(scope : Scope, id : Int, value : Int) -> Bool {
  if scope.disposed || scope.status != 1 || scope.current_id != id {
    false
  } else {
    scope.value = value
    scope.status = 2
    scope.revision += 1
    true
  }
}

///|
pub fn fail(scope : Scope, id : Int, error_code : Int) -> Bool {
  if scope.disposed || scope.status != 1 || scope.current_id != id {
    false
  } else {
    scope.error_code = error_code
    scope.status = 3
    scope.revision += 1
    true
  }
}

///|
pub fn cancel(scope : Scope) -> Bool {
  if scope.disposed || scope.status != 1 {
    false
  } else {
    scope.current_id = 0
    scope.status = 4
    scope.revision += 1
    true
  }
}

///|
pub fn dispose(scope : Scope) -> Bool {
  if scope.disposed {
    false
  } else {
    scope.disposed = true
    scope.current_id = 0
    scope.status = 5
    scope.revision += 1
    true
  }
}

///|
pub fn field(scope : Scope, index : Int) -> Int {
  match index {
    0 => scope.status
    1 => scope.current_id
    2 => scope.value
    3 => scope.error_code
    4 => scope.revision
    5 => if scope.disposed { 1 } else { 0 }
    _ => -1
  }
}
