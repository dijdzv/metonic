///|
pub(all) enum Outcome {
  Changed
  Unchanged
  Rejected
} derive(Debug, Eq)

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
  priv invalidate : () -> Unit
  priv prepare : () -> Work?
}

///|
pub fn replace(invalidate : () -> Unit, prepare : () -> Work?) -> Request {
  { invalidate, prepare, }
}

///|
pub fn cancel(invalidate : () -> Unit) -> Request {
  { invalidate, prepare: () => None, }
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
