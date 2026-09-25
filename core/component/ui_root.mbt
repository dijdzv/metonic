///|
pub struct Read[T] {
  priv sample : () -> T
}

///|
pub fn[T] Read::new(sample : () -> T) -> Read[T] {
  { sample, }
}

///|
pub fn[T] Read::get(self : Read[T]) -> T {
  (self.sample)()
}

///|
pub struct Controlled[T] {
  priv sample : () -> T
  priv commit : (T) -> @task.Request?
}

///|
pub fn[T] Controlled::new(
  sample : () -> T,
  commit : (T) -> @task.Request?,
) -> Controlled[T] {
  { sample, commit, }
}

///|
pub fn[T] Controlled::get(self : Controlled[T]) -> T {
  (self.sample)()
}

///|
priv struct UiAction {
  key : String
  owner : ChildOwner
  reference : @semantics.NodeRef
  callback : () -> @task.Request?
}

///|
priv struct UiEdit {
  key : String
  owner : ChildOwner
  reference : @semantics.NodeRef
  value : Controlled[String]
}

///|
priv struct FixedOwner {
  key : String
  owner : UiOwner
}

///|
pub struct UiRoot {
  priv scope : @reactive.Scope
  priv tree : @semantics.Tree
  priv fixed : Array[FixedOwner]
  priv actions : Array[UiAction]
  priv edits : Array[UiEdit]
}

///|
pub struct UiOwner {
  priv root : UiRoot
  priv child : ChildOwner
}

///|
pub fn UiRoot::new(scope : @reactive.Scope, tree : @semantics.Tree) -> UiRoot {
  if scope.is_disposed() {
    abort("UI root requires a live scope")
  }
  { scope, tree, fixed: [], actions: [], edits: [], }
}

///|
pub fn UiRoot::fixed(self : UiRoot, key : String) -> UiOwner {
  if self.scope.is_disposed() {
    abort("UI root is disposed")
  }
  match
    self.fixed
    .iter()
    .find_first(entry => entry.key == key && entry.owner.child.is_live()) {
    Some(entry) => entry.owner
    None => {
      self.fixed.retain(entry => entry.key != key)
      let owner = UiOwner::{
        root: self,
        child: ChildOwner::new(self.scope, self.tree),
      }
      self.fixed.push({ key, owner, })
      owner
    }
  }
}

///|
pub fn UiRoot::adopt(self : UiRoot, child : ChildOwner) -> UiOwner {
  if self.scope.is_disposed() ||
    !self.scope.contains(child.scope()) ||
    !physical_equal(self.tree, child.tree) ||
    !child.is_live() {
    abort("UI child must belong to the live root scope and semantic tree")
  }
  { root: self, child, }
}

///|
pub fn UiOwner::scope(self : UiOwner) -> @reactive.Scope {
  self.child.scope()
}

///|
pub fn UiOwner::generation(self : UiOwner) -> Int {
  self.child.generation()
}

///|
fn UiOwner::check_key(self : UiOwner, key : String) -> Unit {
  if !self.child.is_live() {
    abort("UI owner is disposed")
  }
  for action in self.root.actions {
    if physical_equal(action.owner.scope(), self.child.scope()) &&
      action.key == key {
      abort("duplicate UI control key")
    }
  }
  for edit in self.root.edits {
    if physical_equal(edit.owner.scope(), self.child.scope()) && edit.key == key {
      abort("duplicate UI control key")
    }
  }
}

///|
pub fn UiOwner::button(
  self : UiOwner,
  key : String,
  label : String,
  on_activate : () -> @task.Request?,
) -> @semantics.NodeRef? {
  self.check_key(key)
  guard self.child.add_button(label) is Some(reference) else { return None }
  self.root.actions.push({
    key,
    owner: self.child,
    reference,
    callback: on_activate,
  })
  self.child
  .scope()
  .on_dispose(() => {
    self.root.actions.retain(action => action.reference != reference)
  })
  Some(reference)
}

///|
pub fn UiOwner::text_input(
  self : UiOwner,
  key : String,
  label : String,
  value : Controlled[String],
) -> @semantics.NodeRef? {
  self.check_key(key)
  let initial = self.root.scope.graph().read_only(() => value.get())
  guard self.child.add_input(label, initial) is Some(reference) else {
    return None
  }
  self.root.edits.push({ key, owner: self.child, reference, value, })
  self.child
  .scope()
  .on_dispose(() => self.root.edits.retain(edit => edit.reference != reference))
  Some(reference)
}

///|
pub fn UiRoot::activate(
  self : UiRoot,
  reference : @semantics.NodeRef,
) -> @task.Request? {
  guard !self.scope.is_disposed() else { return None }
  guard self.actions.iter().find_first(action => action.reference == reference)
    is Some(action) &&
    action.owner.owns(reference) else {
    return None
  }
  guard @semantics.node(self.tree, reference) is Ok(node) &&
    node.role == @semantics.Button &&
    node.enabled else {
    return None
  }
  (action.callback)()
}

///|
pub fn UiRoot::edited(
  self : UiRoot,
  reference : @semantics.NodeRef,
  text : String,
  revision : Int,
) -> @task.Request? {
  guard !self.scope.is_disposed() && revision == @semantics.revision(self.tree) else {
    return None
  }
  guard self.edits.iter().find_first(edit => edit.reference == reference)
    is Some(edit) &&
    edit.owner.owns(reference) else {
    return None
  }
  guard @semantics.node(self.tree, reference) is Ok(node) &&
    node.role == @semantics.TextInput &&
    node.enabled &&
    node.value == text else {
    return None
  }
  (edit.value.commit)(text)
}

///|
pub fn UiRoot::synchronize(
  self : UiRoot,
  composing : @semantics.NodeRef?,
) -> Bool {
  guard !self.scope.is_disposed() else { return false }
  let mut changed = false
  for edit in self.edits {
    if !edit.owner.owns(edit.reference) || composing == Some(edit.reference) {
      continue
    }
    let next = self.scope.graph().read_only(() => edit.value.get())
    if @semantics.node(self.tree, edit.reference) is Ok(node) &&
      node.value != next &&
      @semantics.set_text(self.tree, edit.reference, next) == "" {
      changed = true
    }
  }
  changed
}
