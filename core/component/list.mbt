///|
pub(all) struct ListRow[K] {
  key : K
  label : String
  enabled : Bool
} derive(Eq)

///|
pub(all) enum ListMove {
  Previous
  Next
  First
  Last
} derive(Eq)

///|
priv struct ListRowProps {
  label : String
  enabled : Bool
} derive(Eq)

///|
pub struct UiListItem[K] {
  priv key : K
  priv owner : ChildOwner
  priv root : UiRoot
  priv reference : @semantics.NodeRef
}

///|
pub struct UiList[K] {
  priv root : UiRoot
  priv owner : UiOwner
  priv reference : @semantics.NodeRef
  priv selected : @reactive.Signal[K?]
  priv mut selected_input : PreparedInput[K?]
  priv on_select : (K) -> @task.Request?
  priv rows : KeyedChildren[K, ListRowProps, UiListItem[K]]
  priv mut rows_source : PreparedInput[Array[ListRow[K]]]?
}

///|
priv struct UiListAction {
  key : String
  owner : ChildOwner
  reference : @semantics.NodeRef
  contains : (@semantics.NodeRef) -> Bool
  activate : (@semantics.NodeRef) -> @task.Request?
  navigate : (@semantics.NodeRef, ListMove) -> @semantics.NodeRef?
  synchronize : () -> Bool
}

///|
pub fn[K : Eq] UiOwner::list(
  self : UiOwner,
  key : String,
  label : String,
  selected : @reactive.Signal[K?],
  on_select? : (K) -> @task.Request? = _ => None,
) -> UiList[K]? {
  self.check_key(key)
  guard self.child.add_list(label) is Some(reference) else { return None }
  let list : UiList[K] = {
    root: self.root,
    owner: self,
    reference,
    selected,
    selected_input: PreparedInput::new(
      self.child.scope(),
      Read::new(() => selected.peek()),
    ),
    on_select,
    rows: KeyedChildren::new(self.child.scope(), self.root.tree),
    rows_source: None,
  }
  self.root.lists.push({
    key,
    owner: self.child,
    reference,
    contains: row => list.rows.for_reference(row) is Some(_),
    activate: row => list.activate(row),
    navigate: (row, direction) => list.navigate(row, direction),
    synchronize: () => list.synchronize(),
  })
  self.child
  .scope()
  .on_dispose(() => {
    self.root.lists.retain(entry => entry.reference != reference)
  })
  Some(list)
}

///|
pub fn[K] UiList::reference(self : UiList[K]) -> @semantics.NodeRef {
  self.reference
}

///|
pub fn[K] UiListItem::reference(self : UiListItem[K]) -> @semantics.NodeRef {
  self.reference
}

///|
pub fn[K] UiList::element(
  self : UiList[K],
  bounds : @view.Bounds,
) -> @view.Element {
  if !self.owner.child.owns(self.reference) {
    abort("UI list owner is disposed")
  }
  { bounds, text: "", reference: Some(self.reference), focused: false, }
}

///|
pub fn[K] UiListItem::element(
  self : UiListItem[K],
  bounds : @view.Bounds,
) -> @view.Element {
  if !self.owner.owns(self.reference) {
    abort("UI list item owner is disposed")
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
pub fn[K] UiList::items(self : UiList[K]) -> Array[UiListItem[K]] {
  self.rows.ordered()
}

///|
pub fn[K : Eq] UiList::track_selection(
  self : UiList[K],
  scope : @reactive.Scope,
) -> Unit {
  if !self.owner.child.owns(self.reference) ||
    self.selected_input.read.tracking_scope is Some(_) {
    abort("UI list selection requires a live untracked owner")
  }
  self.selected_input = PreparedInput::new(
    self.owner.child.scope(),
    Read::tracked(scope, () => self.selected.get()),
  )
  ignore(self.synchronize_selection())
}

///|
pub fn[K : Eq] UiList::reconcile(
  self : UiList[K],
  entries : Array[ListRow[K]],
) -> Bool {
  if self.rows_source is Some(_) {
    abort("bound UI list rows cannot be reconciled manually")
  }
  self.reconcile_rows(entries)
}

///|
pub fn[K : Eq] UiList::bind_rows(
  self : UiList[K],
  source : Read[Array[ListRow[K]]],
) -> Unit {
  if self.rows_source is Some(_) || !self.owner.child.owns(self.reference) {
    abort("UI list rows require a live unbound owner")
  }
  let snapshot : Read[Array[ListRow[K]]] = {
    sample: () => source.get().copy(),
    tracking_scope: source.tracking_scope,
    constant: source.constant.map(rows => rows.copy()),
  }
  self.rows_source = Some(
    PreparedInput::new(self.owner.child.scope(), snapshot),
  )
  ignore(self.synchronize())
}

///|
fn[K : Eq] UiList::reconcile_rows(
  self : UiList[K],
  entries : Array[ListRow[K]],
) -> Bool {
  if !self.owner.child.owns(self.reference) {
    abort("UI list owner is disposed")
  }
  let before = self.rows.ordered()
  let mut focused_index = -1
  for index, item in before {
    if @semantics.node(self.root.tree, item.reference) is Ok(node) &&
      node.focused {
      focused_index = index
      break
    }
  }
  let selected = self.selected.peek()
  let selected_was_live = match selected {
    Some(key) => self.rows.get(key) is Some(_)
    None => false
  }
  let changed = self.rows.reconcile(
    entries.map(entry => {
      key: entry.key,
      props: { label: entry.label, enabled: entry.enabled, },
    }),
    (child, key, props) => {
      let reference = child.add_list_item(self.reference, props.label).unwrap()
      if !props.enabled {
        ignore(@semantics.set_enabled(self.root.tree, reference, false))
      }
      UiListItem::{ key, owner: child, root: self.root, reference, }
    },
    (item, props) => {
      ignore(@semantics.set_name(self.root.tree, item.reference, props.label))
      ignore(
        @semantics.set_enabled(self.root.tree, item.reference, props.enabled),
      )
    },
  )
  if selected_was_live &&
    (match selected {
      Some(key) => self.rows.get(key) is None
      None => false
    }) {
    self.selected.set(None)
  }
  let current = self.rows.ordered()
  if focused_index >= 0 &&
    @semantics.node(self.root.tree, before[focused_index].reference) is Err(_) {
    let mut next : @semantics.NodeRef? = None
    for index in focused_index..<current.length() {
      if @semantics.node(self.root.tree, current[index].reference) is Ok(node) &&
        node.enabled {
        next = Some(node.reference)
        break
      }
    }
    if next is None {
      for offset in 0..<focused_index.min(current.length()) {
        let index = focused_index.min(current.length()) - offset - 1
        if @semantics.node(self.root.tree, current[index].reference) is Ok(node) &&
          node.enabled {
          next = Some(node.reference)
          break
        }
      }
    }
    if next is Some(reference) {
      ignore(@semantics.focus(self.root.tree, reference))
    }
  }
  self.selected_input.mark_pending()
  self.synchronize_selection() || changed
}

///|
fn[K : Eq] UiList::synchronize(self : UiList[K]) -> Bool {
  if !self.selected_input.needs_sync() &&
    (match self.rows_source {
      Some(source) => !source.needs_sync()
      None => true
    }) {
    return false
  }
  guard self.owner.child.owns(self.reference) else { return false }
  let mut changed = false
  if self.rows_source is Some(source) {
    let mut rounds = 0
    while source.needs_sync() {
      if rounds >= 16 {
        abort("tracked UI list rows did not stabilize")
      }
      let rows = source.current()
      source.consume()
      changed = self.reconcile_rows(rows) || changed
      rounds += 1
    }
  }
  self.synchronize_selection() || changed
}

///|
fn[K : Eq] UiList::synchronize_selection(self : UiList[K]) -> Bool {
  guard self.selected_input.needs_sync() else { return false }
  guard self.owner.child.owns(self.reference) else { return false }
  let selected = self.selected_input.current()
  let mut changed = false
  let mut complete = true
  for item in self.rows.ordered() {
    if @semantics.node(self.root.tree, item.reference) is Ok(node) {
      let next = selected == Some(item.key)
      if node.selected != next {
        if @semantics.set_selected(self.root.tree, item.reference, next) == "" {
          changed = true
        } else {
          complete = false
        }
      }
    } else {
      complete = false
    }
  }
  if complete {
    self.selected_input.consume()
  }
  changed
}

///|
fn[K] UiList::activate(
  self : UiList[K],
  reference : @semantics.NodeRef,
) -> @task.Request? {
  guard self.rows.for_reference(reference) is Some(item) &&
    @semantics.node(self.root.tree, reference) is Ok(node) &&
    node.enabled else {
    return None
  }
  self.selected.set(Some(item.key))
  (self.on_select)(item.key)
}

///|
fn[K] UiList::navigate(
  self : UiList[K],
  reference : @semantics.NodeRef,
  direction : ListMove,
) -> @semantics.NodeRef? {
  let rows = self.rows.ordered()
  let mut current = -1
  for index, item in rows {
    if item.reference == reference {
      current = index
      break
    }
  }
  guard current >= 0 else { return None }
  let indices : Array[Int] = []
  match direction {
    Next =>
      for index in (current + 1)..<rows.length() {
        indices.push(index)
      }
    Previous =>
      for offset in 0..<current {
        indices.push(current - offset - 1)
      }
    First =>
      for index in 0..<rows.length() {
        indices.push(index)
      }
    Last =>
      for offset in 0..<rows.length() {
        indices.push(rows.length() - offset - 1)
      }
  }
  for index in indices {
    let candidate = rows[index].reference
    if @semantics.node(self.root.tree, candidate) is Ok(node) && node.enabled {
      ignore(@semantics.focus(self.root.tree, candidate))
      return Some(candidate)
    }
  }
  None
}

///|
pub fn UiRoot::navigate_list(
  self : UiRoot,
  reference : @semantics.NodeRef,
  direction : ListMove,
) -> @semantics.NodeRef? {
  guard !self.scope.is_disposed() &&
    @semantics.node(self.tree, reference) is Ok(node) &&
    node.role == @semantics.ListItem else {
    return None
  }
  guard self.lists.iter().find_first(list => (list.contains)(reference))
    is Some(list) else {
    return None
  }
  (list.navigate)(reference, direction)
}
