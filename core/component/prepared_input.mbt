///|
priv struct PreparedInput[T] {
  read : Read[T]
  scope : @reactive.Scope
  desired : Ref[T?]
  pending : Ref[Bool]
}

///|
fn[T : Eq] PreparedInput::new(
  scope : @reactive.Scope,
  read : Read[T],
) -> PreparedInput[T] {
  let prepared : PreparedInput[T] = {
    read,
    scope,
    desired: Ref(read.constant),
    pending: Ref(read.constant is Some(_)),
  }
  if read.tracking_scope is Some(tracking_scope) {
    if !physical_equal(scope.graph(), tracking_scope.graph()) {
      abort("tracked UI input must use its owner's reactive graph")
    }
    let binding = @reactive.Binding::new(tracking_scope, () => read.get(), value => {
      prepared.desired.val = Some(value)
      prepared.pending.val = true
    })
    scope.on_dispose(() => binding.dispose())
  }
  prepared
}

///|
fn[T] PreparedInput::needs_sync(self : PreparedInput[T]) -> Bool {
  if self.read.tracking_scope is Some(_) || self.read.constant is Some(_) {
    self.pending.val
  } else {
    true
  }
}

///|
fn[T] PreparedInput::current(self : PreparedInput[T]) -> T {
  if self.read.tracking_scope is Some(_) || self.read.constant is Some(_) {
    self.desired.val.unwrap()
  } else {
    self.scope.graph().read_only(() => self.read.get())
  }
}

///|
fn[T] PreparedInput::mark_pending(self : PreparedInput[T]) -> Unit {
  self.pending.val = true
}

///|
fn[T] PreparedInput::consume(self : PreparedInput[T]) -> Unit {
  self.pending.val = false
}
