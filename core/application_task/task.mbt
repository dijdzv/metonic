///|
pub(all) enum Outcome {
  Changed
  Unchanged
  Rejected
  Failed(String)
} derive(Debug, Eq)

///|
pub struct Operation {
  priv id : Int
} derive(Eq, Hash)

///|
let next_operation : Ref[Int] = Ref(0)

///|
let default_operation : Operation = { id: 0, }

///|
pub fn Operation::new() -> Operation {
  guard next_operation.val < 0x7fffffff else {
    abort("operation identity exhausted")
  }
  next_operation.val += 1
  { id: next_operation.val, }
}

///|
pub struct Completion {
  priv mut apply_value : (() -> Outcome)?
}

///|
pub fn completion(apply : () -> Outcome) -> Completion {
  { apply_value: Some(apply), }
}

///|
pub fn Completion::apply(self : Completion) -> Outcome {
  guard self.apply_value is Some(apply) else { return Unchanged }
  self.apply_value = None
  apply()
}

///|
pub struct Work {
  priv run : async () -> Completion
}

///|
pub fn[T] work(run : async () -> T, apply : (T) -> Outcome) -> Work {
  {
    run: () => {
      let value = run()
      completion(() => apply(value))
    },
  }
}

///|
pub struct Request {
  priv operation : Operation
  priv on_failure : (String) -> Outcome
  priv invalidate : () -> Unit
  priv prepare : () -> Work?
}

///|
pub fn replace(
  invalidate : () -> Unit,
  prepare : () -> Work?,
  operation? : Operation = default_operation,
  on_failure? : (String) -> Outcome = message => Failed(message),
) -> Request {
  { operation, on_failure, invalidate, prepare, }
}

///|
pub fn cancel(
  invalidate : () -> Unit,
  operation? : Operation = default_operation,
) -> Request {
  {
    operation,
    on_failure: message => Failed(message),
    invalidate,
    prepare: () => None,
  }
}

///|
pub fn Request::operation(self : Request) -> Operation {
  self.operation
}

///|
pub fn Request::failure(self : Request, message : String) -> Completion {
  completion(() => (self.on_failure)(message))
}

///|
pub fn Request::invalidate(self : Request) -> Unit {
  (self.invalidate)()
}

///|
pub fn Request::prepare(self : Request) -> Work? {
  (self.prepare)()
}

///|
pub async fn Work::run(self : Work) -> Completion {
  (self.run)()
}
