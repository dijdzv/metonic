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
  label : Read[String]
  enabled : Read[Bool]
  callback : () -> @task.Request?
}

///|
priv struct UiText {
  key : String
  owner : ChildOwner
  reference : @semantics.NodeRef
  value : Read[String]
}

///|
priv struct UiCheck {
  key : String
  owner : ChildOwner
  reference : @semantics.NodeRef
  label : Read[String]
  value : Controlled[Bool]
  enabled : Read[Bool]
  invalid : Read[Bool]
}

///|
priv struct UiEdit {
  key : String
  owner : ChildOwner
  reference : @semantics.NodeRef
  value : Controlled[String]
  enabled : Read[Bool]
  read_only : Read[Bool]
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
  priv mut theme : @theme.Theme
  priv mut theme_dirty : Bool
  priv fixed : Array[FixedOwner]
  priv actions : Array[UiAction]
  priv checks : Array[UiCheck]
  priv lists : Array[UiListAction]
  priv statuses : Array[UiStatusBinding]
  priv labels : Array[UiText]
  priv edits : Array[UiEdit]
}

///|
pub struct UiOwner {
  priv root : UiRoot
  priv child : ChildOwner
}

///|
pub struct UiButton {
  priv root : UiRoot
  priv owner : ChildOwner
  priv reference : @semantics.NodeRef
}

///|
pub struct UiCheckbox {
  priv root : UiRoot
  priv owner : ChildOwner
  priv reference : @semantics.NodeRef
}

///|
pub struct UiLabel {
  priv root : UiRoot
  priv owner : ChildOwner
  priv reference : @semantics.NodeRef
}

///|
pub struct UiInput {
  priv root : UiRoot
  priv owner : ChildOwner
  priv reference : @semantics.NodeRef
  priv single_line : Bool
}

///|
pub fn UiRoot::new(
  scope : @reactive.Scope,
  tree : @semantics.Tree,
  theme? : @theme.Theme = @theme.default(),
) -> UiRoot {
  if scope.is_disposed() {
    abort("UI root requires a live scope")
  }
  if !theme.valid() {
    abort("invalid UI theme")
  }
  {
    scope,
    tree,
    theme,
    theme_dirty: false,
    fixed: [],
    actions: [],
    checks: [],
    lists: [],
    statuses: [],
    labels: [],
    edits: [],
  }
}

///|
pub fn UiRoot::theme(self : UiRoot) -> @theme.Theme {
  self.theme
}

///|
pub fn UiRoot::set_theme(self : UiRoot, theme : @theme.Theme) -> Bool {
  if self.scope.is_disposed() || !theme.valid() {
    return false
  }
  if self.theme == theme {
    return false
  }
  self.theme = theme
  self.theme_dirty = true
  true
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
  for check in self.root.checks {
    if physical_equal(check.owner.scope(), self.child.scope()) &&
      check.key == key {
      abort("duplicate UI control key")
    }
  }
  for list in self.root.lists {
    if physical_equal(list.owner.scope(), self.child.scope()) && list.key == key {
      abort("duplicate UI control key")
    }
  }
  for status in self.root.statuses {
    if physical_equal(status.owner.scope(), self.child.scope()) &&
      status.key == key {
      abort("duplicate UI control key")
    }
  }
  for edit in self.root.edits {
    if physical_equal(edit.owner.scope(), self.child.scope()) && edit.key == key {
      abort("duplicate UI control key")
    }
  }
  for label in self.root.labels {
    if physical_equal(label.owner.scope(), self.child.scope()) &&
      label.key == key {
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
  enabled? : Read[Bool] = Read::new(() => true),
) -> UiButton? {
  self.check_key(key)
  guard self.child.add_button(label) is Some(reference) else { return None }
  let state = self.root.scope.graph().read_only(() => enabled.get())
  if !state {
    ignore(@semantics.set_enabled(self.root.tree, reference, false))
  }
  self.root.actions.push({
    key,
    owner: self.child,
    reference,
    label: Read::new(() => label),
    enabled,
    callback: on_activate,
  })
  self.child
  .scope()
  .on_dispose(() => {
    self.root.actions.retain(action => action.reference != reference)
  })
  Some({ root: self.root, owner: self.child, reference, })
}

///|
pub fn UiOwner::checkbox(
  self : UiOwner,
  key : String,
  label : String,
  value : Controlled[Bool],
  enabled? : Read[Bool] = Read::new(() => true),
  invalid? : Read[Bool] = Read::new(() => false),
) -> UiCheckbox? {
  self.check_key(key)
  let initial = self.root.scope.graph().read_only(() => value.get())
  guard self.child.add_checkbox(label, initial) is Some(reference) else {
    return None
  }
  let is_enabled = self.root.scope.graph().read_only(() => enabled.get())
  let is_invalid = self.root.scope.graph().read_only(() => invalid.get())
  if !is_enabled {
    ignore(@semantics.set_enabled(self.root.tree, reference, false))
  }
  if is_invalid {
    ignore(@semantics.set_invalid(self.root.tree, reference, true))
  }
  self.root.checks.push({
    key,
    owner: self.child,
    reference,
    label: Read::new(() => label),
    value,
    enabled,
    invalid,
  })
  self.child
  .scope()
  .on_dispose(() => {
    self.root.checks.retain(check => check.reference != reference)
  })
  Some({ root: self.root, owner: self.child, reference, })
}

///|
pub fn UiOwner::label(
  self : UiOwner,
  key : String,
  value : Read[String],
) -> UiLabel? {
  self.check_key(key)
  let text = self.root.scope.graph().read_only(() => value.get())
  guard self.child.add_label(text) is Some(reference) else { return None }
  self.root.labels.push({ key, owner: self.child, reference, value, })
  self.child
  .scope()
  .on_dispose(() => {
    self.root.labels.retain(label => label.reference != reference)
  })
  Some({ root: self.root, owner: self.child, reference, })
}

///|
pub fn UiButton::reference(self : UiButton) -> @semantics.NodeRef {
  self.reference
}

///|
pub fn UiCheckbox::reference(self : UiCheckbox) -> @semantics.NodeRef {
  self.reference
}

///|
pub fn UiLabel::reference(self : UiLabel) -> @semantics.NodeRef {
  self.reference
}

///|
pub fn UiInput::reference(self : UiInput) -> @semantics.NodeRef {
  self.reference
}

///|
pub fn UiInput::single_line(self : UiInput) -> Bool {
  self.single_line
}

///|
pub fn UiButton::element(
  self : UiButton,
  bounds : @view.Bounds,
) -> @view.Element {
  if !self.owner.owns(self.reference) {
    abort("UI button owner is disposed")
  }
  let node = @semantics.node(self.root.tree, self.reference).unwrap()
  {
    bounds,
    text: node.name,
    reference: Some(self.reference),
    focused: node.focused,
  }
}

///|
pub fn UiCheckbox::element(
  self : UiCheckbox,
  bounds : @view.Bounds,
) -> @view.Element {
  if !self.owner.owns(self.reference) {
    abort("UI checkbox owner is disposed")
  }
  let node = @semantics.node(self.root.tree, self.reference).unwrap()
  {
    bounds,
    text: node.name,
    reference: Some(self.reference),
    focused: node.focused,
  }
}

///|
pub fn UiLabel::element(self : UiLabel, bounds : @view.Bounds) -> @view.Element {
  if !self.owner.owns(self.reference) {
    abort("UI label owner is disposed")
  }
  let node = @semantics.node(self.root.tree, self.reference).unwrap()
  { bounds, text: node.name, reference: Some(self.reference), focused: false, }
}

///|
pub fn UiInput::element(self : UiInput, bounds : @view.Bounds) -> @view.Element {
  if !self.owner.owns(self.reference) {
    abort("UI input owner is disposed")
  }
  let node = @semantics.node(self.root.tree, self.reference).unwrap()
  {
    bounds,
    text: node.value,
    reference: Some(self.reference),
    focused: node.focused,
  }
}

///|
pub fn UiOwner::text_input(
  self : UiOwner,
  key : String,
  label : String,
  value : Controlled[String],
  enabled? : Read[Bool] = Read::new(() => true),
  read_only? : Read[Bool] = Read::new(() => false),
) -> UiInput? {
  self.add_text_input(key, label, value, true, enabled, read_only)
}

///|
pub fn UiOwner::text_area(
  self : UiOwner,
  key : String,
  label : String,
  value : Controlled[String],
  enabled? : Read[Bool] = Read::new(() => true),
  read_only? : Read[Bool] = Read::new(() => false),
) -> UiInput? {
  self.add_text_input(key, label, value, false, enabled, read_only)
}

///|
fn UiOwner::add_text_input(
  self : UiOwner,
  key : String,
  label : String,
  value : Controlled[String],
  single_line : Bool,
  enabled : Read[Bool],
  read_only : Read[Bool],
) -> UiInput? {
  self.check_key(key)
  let initial = self.root.scope.graph().read_only(() => value.get())
  guard self.child.add_input(label, initial) is Some(reference) else {
    return None
  }
  let is_enabled = self.root.scope.graph().read_only(() => enabled.get())
  let is_read_only = self.root.scope.graph().read_only(() => read_only.get())
  if !is_enabled {
    ignore(@semantics.set_enabled(self.root.tree, reference, false))
  }
  if is_read_only {
    ignore(@semantics.set_read_only(self.root.tree, reference, true))
  }
  self.root.edits.push({
    key,
    owner: self.child,
    reference,
    value,
    enabled,
    read_only,
  })
  self.child
  .scope()
  .on_dispose(() => self.root.edits.retain(edit => edit.reference != reference))
  Some({ root: self.root, owner: self.child, reference, single_line, })
}

///|
pub fn UiRoot::activate(
  self : UiRoot,
  reference : @semantics.NodeRef,
) -> @task.Request? {
  guard !self.scope.is_disposed() else { return None }
  guard @semantics.node(self.tree, reference) is Ok(node) && node.enabled else {
    return None
  }
  if node.role == @semantics.Button {
    guard self.actions
      .iter()
      .find_first(action => action.reference == reference)
      is Some(action) &&
      action.owner.owns(reference) else {
      return None
    }
    return (action.callback)()
  }
  if node.role == @semantics.Checkbox {
    guard self.checks.iter().find_first(check => check.reference == reference)
      is Some(check) &&
      check.owner.owns(reference) else {
      return None
    }
    return (check.value.commit)(!node.checked)
  }
  if node.role == @semantics.ListItem {
    guard self.lists.iter().find_first(list => (list.contains)(reference))
      is Some(list) else {
      return None
    }
    return (list.activate)(reference)
  }
  None
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
    !node.read_only &&
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
  for action in self.actions {
    if !action.owner.owns(action.reference) {
      continue
    }
    let next_name = self.scope.graph().read_only(() => action.label.get())
    let next_enabled = self.scope.graph().read_only(() => action.enabled.get())
    if @semantics.node(self.tree, action.reference) is Ok(node) {
      if node.name != next_name &&
        @semantics.set_name(self.tree, action.reference, next_name) == "" {
        changed = true
      }
      if node.enabled != next_enabled &&
        @semantics.set_enabled(self.tree, action.reference, next_enabled) == "" {
        changed = true
      }
    }
  }
  for list in self.lists {
    changed = (list.synchronize)() || changed
  }
  for check in self.checks {
    if !check.owner.owns(check.reference) {
      continue
    }
    let next_name = self.scope.graph().read_only(() => check.label.get())
    let next_enabled = self.scope.graph().read_only(() => check.enabled.get())
    let next_checked = self.scope.graph().read_only(() => check.value.get())
    let next_invalid = self.scope.graph().read_only(() => check.invalid.get())
    if @semantics.node(self.tree, check.reference) is Ok(node) {
      if node.name != next_name &&
        @semantics.set_name(self.tree, check.reference, next_name) == "" {
        changed = true
      }
      if node.enabled != next_enabled &&
        @semantics.set_enabled(self.tree, check.reference, next_enabled) == "" {
        changed = true
      }
      if node.checked != next_checked &&
        @semantics.set_checked(self.tree, check.reference, next_checked) == "" {
        changed = true
      }
      if node.invalid != next_invalid &&
        @semantics.set_invalid(self.tree, check.reference, next_invalid) == "" {
        changed = true
      }
    }
  }
  for label in self.labels {
    if !label.owner.owns(label.reference) {
      continue
    }
    let text = self.scope.graph().read_only(() => label.value.get())
    if @semantics.node(self.tree, label.reference) is Ok(node) &&
      node.name != text &&
      @semantics.set_name(self.tree, label.reference, text) == "" {
      changed = true
    }
  }
  for status in self.statuses {
    if !status.owner.owns(status.reference) {
      continue
    }
    let next = self.scope.graph().read_only(() => status.value.get())
    if @semantics.node(self.tree, status.reference) is Ok(node) {
      let message = next.message()
      if node.name != message &&
        @semantics.set_name(self.tree, status.reference, message) == "" {
        changed = true
      }
      let invalid = next.is_error()
      if node.invalid != invalid &&
        @semantics.set_invalid(self.tree, status.reference, invalid) == "" {
        changed = true
      }
    }
  }
  for edit in self.edits {
    if !edit.owner.owns(edit.reference) {
      continue
    }
    let next_enabled = self.scope.graph().read_only(() => edit.enabled.get())
    let next_read_only = self.scope
      .graph()
      .read_only(() => edit.read_only.get())
    if @semantics.node(self.tree, edit.reference) is Ok(node) {
      if node.enabled != next_enabled &&
        @semantics.set_enabled(self.tree, edit.reference, next_enabled) == "" {
        changed = true
      }
      if node.read_only != next_read_only &&
        @semantics.set_read_only(self.tree, edit.reference, next_read_only) ==
        "" {
        changed = true
      }
    }
    if composing == Some(edit.reference) {
      continue
    }
    let next = self.scope.graph().read_only(() => edit.value.get())
    if @semantics.node(self.tree, edit.reference) is Ok(node) &&
      node.value != next &&
      @semantics.set_controlled_text(self.tree, edit.reference, next) == "" {
      changed = true
    }
  }
  if self.theme_dirty {
    self.theme_dirty = false
    changed = true
  }
  changed
}
