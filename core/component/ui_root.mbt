///|
pub struct Read[T] {
  priv sample : () -> T
  priv tracking_scope : @reactive.Scope?
  priv constant : T?
}

///|
pub fn[T] Read::new(sample : () -> T) -> Read[T] {
  { sample, tracking_scope: None, constant: None, }
}

///|
pub fn[T] Read::constant(value : T) -> Read[T] {
  { sample: () => value, tracking_scope: None, constant: Some(value), }
}

///|
pub fn[T] Read::tracked(scope : @reactive.Scope, sample : () -> T) -> Read[T] {
  { sample, tracking_scope: Some(scope), constant: None, }
}

///|
pub fn[T] Read::get(self : Read[T]) -> T {
  (self.sample)()
}

///|
pub struct Controlled[T] {
  priv sample : () -> T
  priv commit : (T) -> @task.Request?
  priv tracking_scope : @reactive.Scope?
}

///|
pub fn[T] Controlled::new(
  sample : () -> T,
  commit : (T) -> @task.Request?,
) -> Controlled[T] {
  { sample, commit, tracking_scope: None, }
}

///|
pub fn[T] Controlled::tracked(
  scope : @reactive.Scope,
  sample : () -> T,
  commit : (T) -> @task.Request?,
) -> Controlled[T] {
  { sample, commit, tracking_scope: Some(scope), }
}

///|
pub fn[T] Controlled::get(self : Controlled[T]) -> T {
  (self.sample)()
}

///|
fn[T] Controlled::as_read(self : Controlled[T]) -> Read[T] {
  { sample: self.sample, tracking_scope: self.tracking_scope, constant: None, }
}

///|
priv struct UiAction {
  key : String
  owner : ChildOwner
  reference : @semantics.NodeRef
  label : PreparedInput[String]
  enabled : PreparedInput[Bool]
  callback : () -> @task.Request?
}

///|
priv struct UiText {
  key : String
  owner : ChildOwner
  reference : @semantics.NodeRef
  value : PreparedInput[String]
}

///|
priv struct UiCheck {
  key : String
  owner : ChildOwner
  reference : @semantics.NodeRef
  label : PreparedInput[String]
  value : Controlled[Bool]
  desired_value : PreparedInput[Bool]
  enabled : PreparedInput[Bool]
  invalid : PreparedInput[Bool]
}

///|
priv struct UiEdit {
  key : String
  owner : ChildOwner
  reference : @semantics.NodeRef
  value : Controlled[String]
  desired_value : PreparedInput[String]
  enabled : PreparedInput[Bool]
  read_only : PreparedInput[Bool]
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
  enabled? : Read[Bool] = Read::constant(true),
) -> UiButton? {
  self.check_key(key)
  guard self.child.add_button(label) is Some(reference) else { return None }
  let prepared_enabled = PreparedInput::new(self.child.scope(), enabled)
  let state = prepared_enabled.current()
  if !state {
    ignore(@semantics.set_enabled(self.root.tree, reference, false))
  }
  prepared_enabled.consume()
  let prepared_label = PreparedInput::new(
    self.child.scope(),
    Read::constant(label),
  )
  prepared_label.consume()
  self.root.actions.push({
    key,
    owner: self.child,
    reference,
    label: prepared_label,
    enabled: prepared_enabled,
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
  enabled? : Read[Bool] = Read::constant(true),
  invalid? : Read[Bool] = Read::constant(false),
) -> UiCheckbox? {
  self.check_key(key)
  let prepared_value = PreparedInput::new(self.child.scope(), value.as_read())
  let prepared_enabled = PreparedInput::new(self.child.scope(), enabled)
  let prepared_invalid = PreparedInput::new(self.child.scope(), invalid)
  let initial = prepared_value.current()
  guard self.child.add_checkbox(label, initial) is Some(reference) else {
    return None
  }
  let is_enabled = prepared_enabled.current()
  let is_invalid = prepared_invalid.current()
  if !is_enabled {
    ignore(@semantics.set_enabled(self.root.tree, reference, false))
  }
  if is_invalid {
    ignore(@semantics.set_invalid(self.root.tree, reference, true))
  }
  prepared_value.consume()
  prepared_enabled.consume()
  prepared_invalid.consume()
  let prepared_label = PreparedInput::new(
    self.child.scope(),
    Read::constant(label),
  )
  prepared_label.consume()
  self.root.checks.push({
    key,
    owner: self.child,
    reference,
    label: prepared_label,
    value,
    desired_value: prepared_value,
    enabled: prepared_enabled,
    invalid: prepared_invalid,
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
  let prepared_value = PreparedInput::new(self.child.scope(), value)
  let text = prepared_value.current()
  guard self.child.add_label(text) is Some(reference) else { return None }
  prepared_value.consume()
  self.root.labels.push({
    key,
    owner: self.child,
    reference,
    value: prepared_value,
  })
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
  enabled? : Read[Bool] = Read::constant(true),
  read_only? : Read[Bool] = Read::constant(false),
) -> UiInput? {
  self.add_text_input(key, label, value, true, enabled, read_only)
}

///|
pub fn UiOwner::text_area(
  self : UiOwner,
  key : String,
  label : String,
  value : Controlled[String],
  enabled? : Read[Bool] = Read::constant(true),
  read_only? : Read[Bool] = Read::constant(false),
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
  let prepared_value = PreparedInput::new(self.child.scope(), value.as_read())
  let prepared_enabled = PreparedInput::new(self.child.scope(), enabled)
  let prepared_read_only = PreparedInput::new(self.child.scope(), read_only)
  let initial = prepared_value.current()
  guard self.child.add_input(label, initial) is Some(reference) else {
    return None
  }
  let is_enabled = prepared_enabled.current()
  let is_read_only = prepared_read_only.current()
  if !is_enabled {
    ignore(@semantics.set_enabled(self.root.tree, reference, false))
  }
  if is_read_only {
    ignore(@semantics.set_read_only(self.root.tree, reference, true))
  }
  prepared_value.consume()
  prepared_enabled.consume()
  prepared_read_only.consume()
  self.root.edits.push({
    key,
    owner: self.child,
    reference,
    value,
    desired_value: prepared_value,
    enabled: prepared_enabled,
    read_only: prepared_read_only,
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
    let request = (check.value.commit)(!node.checked)
    check.desired_value.mark_pending()
    return request
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
  let request = (edit.value.commit)(text)
  edit.desired_value.mark_pending()
  request
}

///|
fn UiRoot::sync_name(
  self : UiRoot,
  reference : @semantics.NodeRef,
  input : PreparedInput[String],
) -> Bool {
  guard input.needs_sync() else { return false }
  let desired = input.current()
  guard @semantics.node(self.tree, reference) is Ok(node) else { return false }
  if node.name == desired {
    input.consume()
    return false
  }
  let changed = @semantics.set_name(self.tree, reference, desired) == ""
  if changed {
    input.consume()
  }
  changed
}

///|
fn UiRoot::sync_enabled(
  self : UiRoot,
  reference : @semantics.NodeRef,
  input : PreparedInput[Bool],
) -> Bool {
  guard input.needs_sync() else { return false }
  let desired = input.current()
  guard @semantics.node(self.tree, reference) is Ok(node) else { return false }
  if node.enabled == desired {
    input.consume()
    return false
  }
  let changed = @semantics.set_enabled(self.tree, reference, desired) == ""
  if changed {
    input.consume()
  }
  changed
}

///|
fn UiRoot::sync_checked(
  self : UiRoot,
  reference : @semantics.NodeRef,
  input : PreparedInput[Bool],
) -> Bool {
  guard input.needs_sync() else { return false }
  let desired = input.current()
  guard @semantics.node(self.tree, reference) is Ok(node) else { return false }
  if node.checked == desired {
    input.consume()
    return false
  }
  let changed = @semantics.set_checked(self.tree, reference, desired) == ""
  if changed {
    input.consume()
  }
  changed
}

///|
fn UiRoot::sync_invalid(
  self : UiRoot,
  reference : @semantics.NodeRef,
  input : PreparedInput[Bool],
) -> Bool {
  guard input.needs_sync() else { return false }
  let desired = input.current()
  guard @semantics.node(self.tree, reference) is Ok(node) else { return false }
  if node.invalid == desired {
    input.consume()
    return false
  }
  let changed = @semantics.set_invalid(self.tree, reference, desired) == ""
  if changed {
    input.consume()
  }
  changed
}

///|
fn UiRoot::sync_read_only(
  self : UiRoot,
  reference : @semantics.NodeRef,
  input : PreparedInput[Bool],
) -> Bool {
  guard input.needs_sync() else { return false }
  let desired = input.current()
  guard @semantics.node(self.tree, reference) is Ok(node) else { return false }
  if node.read_only == desired {
    input.consume()
    return false
  }
  let changed = @semantics.set_read_only(self.tree, reference, desired) == ""
  if changed {
    input.consume()
  }
  changed
}

///|
fn UiRoot::sync_text(
  self : UiRoot,
  reference : @semantics.NodeRef,
  input : PreparedInput[String],
) -> Bool {
  guard input.needs_sync() else { return false }
  let desired = input.current()
  guard @semantics.node(self.tree, reference) is Ok(node) else { return false }
  if node.value == desired {
    input.consume()
    return false
  }
  let changed = @semantics.set_controlled_text(self.tree, reference, desired) ==
    ""
  if changed {
    input.consume()
  }
  changed
}

///|
pub fn UiRoot::synchronize(
  self : UiRoot,
  composing : @semantics.NodeRef?,
) -> Bool {
  guard !self.scope.is_disposed() else { return false }
  let mut changed = false
  for action in self.actions {
    if !action.label.needs_sync() && !action.enabled.needs_sync() {
      continue
    }
    if !action.owner.owns(action.reference) {
      continue
    }
    changed = self.sync_name(action.reference, action.label) || changed
    changed = self.sync_enabled(action.reference, action.enabled) || changed
  }
  for list in self.lists {
    changed = (list.synchronize)() || changed
  }
  for check in self.checks {
    if !check.label.needs_sync() &&
      !check.enabled.needs_sync() &&
      !check.desired_value.needs_sync() &&
      !check.invalid.needs_sync() {
      continue
    }
    if !check.owner.owns(check.reference) {
      continue
    }
    changed = self.sync_name(check.reference, check.label) || changed
    changed = self.sync_enabled(check.reference, check.enabled) || changed
    changed = self.sync_checked(check.reference, check.desired_value) || changed
    changed = self.sync_invalid(check.reference, check.invalid) || changed
  }
  for label in self.labels {
    if !label.value.needs_sync() {
      continue
    }
    if !label.owner.owns(label.reference) {
      continue
    }
    changed = self.sync_name(label.reference, label.value) || changed
  }
  for status in self.statuses {
    if !status.value.needs_sync() {
      continue
    }
    if !status.owner.owns(status.reference) {
      continue
    }
    let next = status.value.current()
    if @semantics.node(self.tree, status.reference) is Ok(node) {
      let message = next.message()
      let name_ok = node.name == message ||
        @semantics.set_name(self.tree, status.reference, message) == ""
      if name_ok && node.name != message {
        changed = true
      }
      let invalid = next.is_error()
      let invalid_ok = node.invalid == invalid ||
        @semantics.set_invalid(self.tree, status.reference, invalid) == ""
      if invalid_ok && node.invalid != invalid {
        changed = true
      }
      if name_ok && invalid_ok {
        status.value.consume()
      }
    }
  }
  for edit in self.edits {
    if !edit.enabled.needs_sync() &&
      !edit.read_only.needs_sync() &&
      !edit.desired_value.needs_sync() &&
      composing != Some(edit.reference) {
      continue
    }
    if !edit.owner.owns(edit.reference) {
      continue
    }
    changed = self.sync_enabled(edit.reference, edit.enabled) || changed
    changed = self.sync_read_only(edit.reference, edit.read_only) || changed
    if composing == Some(edit.reference) {
      edit.desired_value.mark_pending()
      continue
    }
    changed = self.sync_text(edit.reference, edit.desired_value) || changed
  }
  if self.theme_dirty {
    self.theme_dirty = false
    changed = true
  }
  changed
}
