///|
pub(all) struct ChildSpec[K, P] {
  key : K
  props : P
}

///|
pub struct ChildOwner {
  priv scope : @reactive.Scope
  priv tree : @semantics.Tree
  priv references : Array[@semantics.NodeRef]
  priv generation : Int
}

///|
priv struct ChildEntry[K, P, V] {
  key : K
  mut props : P
  owner : ChildOwner
  value : V
  mut active : Bool
}

///|
pub struct KeyedChildren[K, P, V] {
  priv parent : @reactive.Scope
  priv tree : @semantics.Tree
  priv entries : Array[ChildEntry[K, P, V]]
  priv mut reconciling : Bool
}

///|
let next_child_generation : Ref[Int] = Ref(0)

///|
fn ChildOwner::new(
  parent : @reactive.Scope,
  tree : @semantics.Tree,
) -> ChildOwner {
  guard next_child_generation.val < 0x7fffffff else {
    abort("component generation exhausted")
  }
  next_child_generation.val += 1
  let scope = parent.child()
  let owner : ChildOwner = {
    scope,
    tree,
    references: [],
    generation: next_child_generation.val,
  }
  scope.on_dispose(() => {
    for reference in owner.references {
      ignore(@semantics.remove(tree, reference))
    }
    owner.references.clear()
  })
  owner
}

///|
pub fn ChildOwner::scope(self : ChildOwner) -> @reactive.Scope {
  self.scope
}

///|
pub fn ChildOwner::generation(self : ChildOwner) -> Int {
  self.generation
}

///|
pub fn ChildOwner::is_live(self : ChildOwner) -> Bool {
  !self.scope.is_disposed()
}

///|
pub fn ChildOwner::add_button(
  self : ChildOwner,
  name : String,
) -> @semantics.NodeRef? {
  guard !self.scope.is_disposed() else { return None }
  let reference = @semantics.add_button(self.tree, name)
  if reference is Some(value) {
    self.references.push(value)
  }
  reference
}

///|
pub fn ChildOwner::add_checkbox(
  self : ChildOwner,
  name : String,
  checked : Bool,
) -> @semantics.NodeRef? {
  guard !self.scope.is_disposed() else { return None }
  let reference = @semantics.add_checkbox(self.tree, name, checked)
  if reference is Some(value) {
    self.references.push(value)
  }
  reference
}

///|
pub fn ChildOwner::add_label(
  self : ChildOwner,
  text : String,
) -> @semantics.NodeRef? {
  guard !self.scope.is_disposed() else { return None }
  let reference = @semantics.add_label(self.tree, text)
  if reference is Some(value) {
    self.references.push(value)
  }
  reference
}

///|
pub fn ChildOwner::add_input(
  self : ChildOwner,
  name : String,
  value : String,
) -> @semantics.NodeRef? {
  guard !self.scope.is_disposed() else { return None }
  let reference = @semantics.add_input(self.tree, name, value)
  if reference is Some(value) {
    self.references.push(value)
  }
  reference
}

///|
pub fn ChildOwner::owns(
  self : ChildOwner,
  reference : @semantics.NodeRef,
) -> Bool {
  !self.scope.is_disposed() &&
  self.references.contains(reference) &&
  @semantics.node(self.tree, reference) is Ok(_)
}

///|
pub fn[K, P, V] KeyedChildren::new(
  parent : @reactive.Scope,
  tree : @semantics.Tree,
) -> KeyedChildren[K, P, V] {
  if parent.is_disposed() {
    abort("keyed components require a live parent scope")
  }
  let children : KeyedChildren[K, P, V] = {
    parent,
    tree,
    entries: [],
    reconciling: false,
  }
  parent.on_dispose(() => children.entries.clear())
  children
}

///|
pub fn[K : Eq, P : Eq, V] KeyedChildren::reconcile(
  self : KeyedChildren[K, P, V],
  specs : Array[ChildSpec[K, P]],
  create : (ChildOwner, K, P) -> V,
  update : (V, P) -> Unit,
) -> Bool {
  if self.parent.is_disposed() || self.reconciling {
    abort("keyed component reconciliation requires a live idle parent")
  }
  for i = 0; i < specs.length(); i = i + 1 {
    for j = i + 1; j < specs.length(); j = j + 1 {
      if specs[i].key == specs[j].key {
        abort("duplicate keyed component identity")
      }
    }
  }
  self.reconciling = true
  defer {
    self.reconciling = false
  }
  self.parent
  .graph()
  .batch(() => {
    let mut changed = self.entries.length() != specs.length()
    for entry in self.entries {
      if !specs.any(spec => spec.key == entry.key) {
        entry.active = false
        entry.owner.scope.dispose()
      }
    }
    let next : Array[ChildEntry[K, P, V]] = []
    for index, spec in specs {
      let existing = self.entries
        .iter()
        .find_first(entry => entry.active && entry.key == spec.key)
      match existing {
        Some(entry) => {
          if index >= self.entries.length() ||
            self.entries[index].key != spec.key {
            changed = true
          }
          if entry.props != spec.props {
            update(entry.value, spec.props)
            entry.props = spec.props
            changed = true
          }
          next.push(entry)
        }
        None => {
          let owner = ChildOwner::new(self.parent, self.tree)
          let value = create(owner, spec.key, spec.props)
          if owner.scope.is_disposed() {
            abort("keyed component disposed during construction")
          }
          let entry : ChildEntry[K, P, V] = {
            key: spec.key,
            props: spec.props,
            owner,
            value,
            active: true,
          }
          owner.scope.on_dispose(() => entry.active = false)
          next.push(entry)
          changed = true
        }
      }
    }
    self.entries.clear()
    for entry in next {
      self.entries.push(entry)
    }
    changed
  })
}

///|
pub fn[K : Eq, P, V] KeyedChildren::get(
  self : KeyedChildren[K, P, V],
  key : K,
) -> V? {
  guard !self.parent.is_disposed() else { return None }
  self.entries
  .iter()
  .find_first(entry => entry.active && entry.key == key)
  .map(entry => entry.value)
}

///|
pub fn[K, P, V] KeyedChildren::for_reference(
  self : KeyedChildren[K, P, V],
  reference : @semantics.NodeRef,
) -> V? {
  guard !self.parent.is_disposed() else { return None }
  self.entries
  .iter()
  .find_first(entry => entry.active && entry.owner.owns(reference))
  .map(entry => entry.value)
}

///|
pub fn[K, P, V] KeyedChildren::ordered(
  self : KeyedChildren[K, P, V],
) -> Array[V] {
  guard !self.parent.is_disposed() else { return [] }
  self.entries.filter(entry => entry.active).map(entry => entry.value)
}

///|
pub fn[K, P, V] KeyedChildren::clear(self : KeyedChildren[K, P, V]) -> Bool {
  guard !self.parent.is_disposed() else { return false }
  if self.reconciling {
    abort("keyed component reconciliation cannot re-enter")
  }
  self.reconciling = true
  defer {
    self.reconciling = false
  }
  let changed = !self.entries.is_empty()
  self.parent
  .graph()
  .batch(() => {
    for entry in self.entries {
      entry.active = false
      entry.owner.scope.dispose()
    }
    self.entries.clear()
  })
  changed
}
