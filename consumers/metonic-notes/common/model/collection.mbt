///|
priv struct Collection {
  graph : @reactive.Graph
  scope : @reactive.Scope
  visible_rows : @reactive.Memo[Array[Int]]
  selected_row : @reactive.Memo[Int?]
  presentation : @reactive.Signal[PresentationRuntime]
  tree : @semantics.Tree
  input : @semantics.NodeRef
  search_input : @semantics.NodeRef
  search : @search.Model
  list : @layout.VerticalList
  mut buttons : Array[@semantics.NodeRef]
  mut row_ids : Array[Int]
  mut reveal_selected : Bool
  persistence : @persistence.Model
  store : @persistence.Store
  save_operation : @task.Operation
  wait : async (Int) -> Unit
  mut save_waiting : Bool
  workspace : @reactive.Signal[@collection.WorkspaceState]
  mut size : (Int, Int)
  mut error : String?
  mut input_error : String?
  mut close_pending : Bool
  mut close_confirmed : Bool
}

///|
fn Collection::reconcile_rows(self : Collection, ids : Array[Int]) -> Unit {
  let next_buttons = self.buttons.iter().take(6).to_array()
  for id in ids {
    let mut retained : @semantics.NodeRef? = None
    for index, old_id in self.row_ids {
      if old_id == id {
        retained = Some(self.buttons[index + 6])
        break
      }
    }
    let reference = match retained {
      Some(reference) => reference
      None =>
        @semantics.add_button(self.tree, "Memo " + id.to_string()).unwrap()
    }
    next_buttons.push(reference)
  }
  for index, id in self.row_ids {
    if !ids.contains(id) {
      ignore(@semantics.remove(self.tree, self.buttons[index + 6]))
    }
  }
  self.buttons = next_buttons
  self.row_ids = ids.copy()
}

///|
fn Collection::present_rows(
  self : Collection,
  ids : Array[Int],
  selected : Int?,
  enabled : Bool,
) -> Unit {
  for index, id in ids {
    let reference = self.buttons[index + 6]
    let name = (if selected == Some(id) { "* " } else { "" }) +
      "Memo " +
      id.to_string()
    let node = @semantics.node(self.tree, reference).unwrap()
    if node.name != name {
      ignore(@semantics.set_name(self.tree, reference, name))
    }
    if node.enabled != enabled {
      ignore(@semantics.set_enabled(self.tree, reference, enabled))
    }
  }
}

///|
fn Collection::ready(self : Collection) -> Bool {
  match self.persistence.state() {
    Ready | Saving | SaveFailed(_) => true
    _ => false
  }
}

///|
fn Collection::flush(self : Collection) -> Bool {
  let workspace = self.workspace.peek()
  guard workspace.active() is Some(note) else { return true }
  let value = @semantics.node(self.tree, self.input).unwrap().value
  if value == note.text {
    return true
  }
  match workspace.edit(value) {
    Ok(next) => {
      self.set_workspace(next)
      true
    }
    Err(message) => {
      self.error = Some(message)
      false
    }
  }
}

///|
fn Collection::dirty(self : Collection) -> Bool {
  let workspace = self.workspace.peek()
  workspace.dirty() ||
  (match workspace.active() {
    Some(note) =>
      @semantics.node(self.tree, self.input).unwrap().value != note.text
    None => false
  })
}

///|
fn Collection::set_workspace(
  self : Collection,
  workspace : @collection.WorkspaceState,
) -> Unit {
  self.graph.batch(() => {
    self.workspace.set(workspace)
    self.search.refresh(workspace.snapshot())
  })
}

///|
fn Collection::show_selected(self : Collection) -> Unit {
  self.reveal_selected = true
}

///|
fn Collection::sync(self : Collection, replace_input? : Bool = false) -> Unit {
  let workspace = self.workspace.peek()
  let runtime : PresentationRuntime = {
    persistence: self.persistence.state(),
    close_pending: self.close_pending,
    save_waiting: self.save_waiting,
    filtered: self.search.filtered(),
  }
  if replace_input {
    ignore(@semantics.set_enabled(self.tree, self.input, true))
    ignore(
      @semantics.set_text(
        self.tree,
        self.input,
        workspace.active().map(n => n.text).unwrap_or(""),
      ),
    )
    ignore(
      @semantics.set_enabled(
        self.tree,
        self.input,
        runtime.ready() && workspace.active() is Some(_) &&
        !runtime.close_pending,
      ),
    )
  }
  self.presentation.set(runtime)
}

///|
fn Collection::load(self : Collection) -> @task.Request? {
  let request = self.persistence.load_request(self.store, () => {
    if self.persistence.state() == @persistence.Ready {
      self.set_workspace(
        @collection.workspace_state(
          @collection.decode(Some(self.persistence.text())).unwrap(),
        ),
      )
      self.show_selected()
    }
    self.sync(replace_input=true)
  })
  self.sync()
  request
}

///|
fn Collection::activate(
  self : Collection,
  reference : @semantics.NodeRef,
) -> @task.Request? {
  self.graph.batch(() => self.activate_inner(reference))
}

///|
fn Collection::activate_inner(
  self : Collection,
  reference : @semantics.NodeRef,
) -> @task.Request? {
  guard self.buttons.iter().find_first(r => r == reference) is Some(_) else {
    return None
  }
  guard @semantics.node(self.tree, reference) is Ok(node) && node.enabled else {
    return None
  }
  if reference == self.buttons[1] &&
    self.persistence.state() == @persistence.Saving {
    guard self.save_waiting else { return None }
    return Some(
      @task.replace(
        () => (),
        () => {
          self.persistence.retire_save()
          let mut workspace = self.workspace.peek()
          if self.persistence.saved_text() is Some(saved) &&
            @collection.decode(Some(saved)) is Ok(document) {
            workspace = workspace.acknowledge_save(document)
          }
          self.set_workspace(workspace.discard())
          ignore(self.persistence.discard())
          self.save_waiting = false
          self.error = None
          if self.close_pending {
            self.close_confirmed = true
          }
          self.show_selected()
          self.sync(replace_input=true)
          None
        },
        operation=self.save_operation,
      ),
    )
  }
  if self.close_pending && reference == self.buttons[2] {
    self.close_pending = false
    self.close_confirmed = false
    self.sync()
    if self.workspace.peek().active() is Some(_) {
      ignore(@semantics.focus(self.tree, self.input))
    }
    return None
  }
  if self.close_pending && reference == self.buttons[1] {
    // Discard must remain possible even when the draft fails save validation.
    self.set_workspace(self.workspace.peek().discard())
    ignore(self.persistence.discard())
    self.error = None
    self.close_confirmed = true
    self.show_selected()
    self.sync(replace_input=true)
    return Some(@task.cancel(() => (), operation=self.save_operation))
  }
  if reference == self.buttons[0] &&
    self.persistence.state() is @persistence.LoadFailed(_) {
    return self.load()
  }
  guard self.ready() && self.flush() else { return None }
  self.error = None
  let previous_active = self.workspace.peek().active().map(note => note.id)
  if reference == self.buttons[0] {
    if self.close_pending {
      self.close_confirmed = true
    }
    return self.save(0)
  }
  if reference == self.buttons[4] || reference == self.buttons[5] {
    if self.search.filtered() {
      self.sync()
      return None
    }
    let (next, changed) = self.workspace
      .peek()
      .reorder_selected(
        if reference == self.buttons[4] {
          @collection.MoveDirection::Up
        } else {
          @collection.MoveDirection::Down
        },
      )
    self.set_workspace(next)
    self.show_selected()
    self.sync()
    return if changed { self.save(500) } else { None }
  }
  if reference == self.buttons[1] {
    self.set_workspace(self.workspace.peek().discard())
    ignore(self.persistence.discard())
    self.show_selected()
  } else if reference == self.buttons[2] {
    match self.workspace.peek().create_note() {
      Ok((next, _)) => self.set_workspace(next)
      Err(message) => self.error = Some(message)
    }
    self.show_selected()
  } else if reference == self.buttons[3] {
    if self.workspace.peek().deletion_pending() {
      let (next, _) = self.workspace.peek().confirm_delete()
      self.set_workspace(next)
      self.show_selected()
    } else {
      let (next, _) = self.workspace.peek().request_delete()
      self.set_workspace(next)
    }
  } else {
    for i in 6..<self.buttons.length() {
      if reference == self.buttons[i] && self.row_ids.get(i - 6) is Some(id) {
        if self.workspace.peek().select(id) is Some(next) {
          self.set_workspace(next)
          self.show_selected()
        }
      }
    }
  }
  self.sync(
    replace_input=reference == self.buttons[1] ||
    self.workspace.peek().active().map(note => note.id) != previous_active,
  )
  if reference == self.buttons[1] ||
    reference == self.buttons[2] ||
    (reference == self.buttons[3] && !self.workspace.peek().deletion_pending()) ||
    self.buttons[6:].contains(reference) {
    ignore(
      @semantics.focus(
        self.tree,
        if self.workspace.peek().active() is Some(_) {
          self.input
        } else {
          self.buttons[2]
        },
      ),
    )
  }
  if reference == self.buttons[1] {
    Some(@task.cancel(() => (), operation=self.save_operation))
  } else if reference == self.buttons[2] ||
    (reference == self.buttons[3] && !self.workspace.peek().deletion_pending()) {
    self.save(500)
  } else {
    None
  }
}

///|
fn Collection::status(self : Collection) -> String {
  let primary = if self.error is Some(error) {
    error
  } else {
    match self.persistence.state() {
      Unloaded | Loading => "Loading..."
      Saving => "Saving..."
      LoadFailed(message) => "Load failed: " + message
      SaveFailed(message) => "Save failed: " + message
      Closed => "Closed"
      Ready => if self.dirty() { "Unsaved changes" } else { "Saved" }
    }
  }
  let primary = if self.close_pending { "Close? " + primary } else { primary }
  match self.input_error {
    Some(error) => primary + " | " + error
    None => primary
  }
}

///|
fn Collection::view(self : Collection) -> Array[@application.Control] {
  let input = @semantics.node(self.tree, self.input).unwrap()
  let layout = collection_layout(self.size.0, self.size.1)
  let references = self.buttons[6:].to_owned()
  self.list.arrange(layout.list, references).unwrap()
  if self.reveal_selected {
    if self.workspace.peek().active() is Some(selected) {
      for index, id in self.row_ids {
        if id == selected.id {
          ignore(self.list.reveal(self.buttons[index + 6]))
        }
      }
    }
    self.reveal_selected = false
  }
  let rows = self.list.items()
  let compact = self.size.0 < 640 || self.size.1 < 448
  let controls : Array[@application.Control] = [
    {
      element: {
        bounds: layout.editor,
        text: input.value,
        reference: Some(self.input),
        focused: input.focused,
      },
      kind: @application.Input(single_line=false),
      clip: None,
    },
  ]
  for i, reference in self.buttons {
    if i < 6 || rows[i - 6].visible is Some(_) {
      let node = @semantics.node(self.tree, reference).unwrap()
      let label = if self.close_pending {
        node.name
      } else if compact && i == 1 {
        "Discard all"
      } else if compact && i == 3 {
        if self.workspace.peek().deletion_pending() {
          "Confirm"
        } else {
          "Delete"
        }
      } else {
        node.name
      }
      let bounds = if i < 6 { layout.actions[i] } else { rows[i - 6].bounds }
      controls.push({
        element: {
          bounds,
          text: label,
          reference: Some(reference),
          focused: node.focused,
        },
        kind: @application.Button,
        clip: if i < 6 {
          None
        } else {
          Some(layout.list)
        },
      })
    }
  }
  let query = @semantics.node(self.tree, self.search_input).unwrap()
  controls.push({
    element: {
      bounds: layout.search_label,
      text: "Search",
      reference: None,
      focused: false,
    },
    kind: @application.Text,
    clip: None,
  })
  controls.push({
    element: {
      bounds: layout.search,
      text: query.value,
      reference: Some(self.search_input),
      focused: query.focused,
    },
    kind: @application.Input(single_line=true),
    clip: None,
  })
  controls.push({
    element: {
      bounds: layout.status,
      text: self.status(),
      reference: None,
      focused: false,
    },
    kind: @application.Text,
    clip: None,
  })
  controls
}

///|
pub fn create_collection(
  store : @persistence.Store,
  dispose : async () -> Unit,
  wait : async (Int) -> Unit,
) -> @application.Application {
  let graph = @reactive.Graph::new()
  let scope = @reactive.Scope::root(graph)
  let workspace = @reactive.Signal::new(
    scope,
    @collection.workspace_state(@collection.empty()),
  )
  let search = @search.create(scope, wait)
  let visible_rows : @reactive.Memo[Array[Int]] = @reactive.Memo::new(
    scope,
    () => search.items().map(note => note.id),
  )
  let selected_row : @reactive.Memo[Int?] = @reactive.Memo::new(scope, () => {
    workspace.get().active().map(note => note.id)
  })
  let presentation = @reactive.Signal::new(
    scope,
    {
      persistence: @persistence.Unloaded,
      close_pending: false,
      save_waiting: false,
      filtered: false,
    },
  )
  let tree = @semantics.empty(1, 1)
  let input = @semantics.add_input(tree, "Memo", "").unwrap()
  let search_input = @semantics.add_input(tree, "Search memos", "").unwrap()
  let buttons = Array::makei(6, _ => {
    @semantics.add_button(tree, "Loading").unwrap()
  })
  let model : Collection = {
    graph,
    scope,
    visible_rows,
    selected_row,
    presentation,
    tree,
    input,
    search_input,
    search,
    list: @layout.VerticalList::new(row_height=32, gap=4).unwrap(),
    buttons,
    row_ids: [],
    reveal_selected: false,
    persistence: @persistence.create(),
    save_operation: @task.Operation::new(),
    wait,
    save_waiting: false,
    store: {
      load: () => {
        match (store.load)() {
          Err(error) => Err(error)
          Ok(value) =>
            match @collection.decode(value) {
              Err(error) => Err(error)
              Ok(document) => Ok(Some(document.encode()))
            }
        }
      },
      save: store.save,
    },
    workspace,
    size: (760, 520),
    error: None,
    input_error: None,
    close_pending: false,
    close_confirmed: false,
  }
  let tasks_connected = Ref(false)
  let _ = @reactive.Binding::new(
    scope,
    () => {
      (
        model.visible_rows.get(),
        model.selected_row.get(),
        model.presentation.get().ready() &&
        !model.presentation.get().close_pending,
      )
    },
    state => {
      let (ids, selected, enabled) = state
      if model.row_ids != ids {
        model.reconcile_rows(ids)
      }
      model.present_rows(ids, selected, enabled)
    },
  )
  let _ = @reactive.Binding::new(
    scope,
    () => {
      let runtime = model.presentation.get()
      let workspace = model.workspace.get()
      (
        runtime.ready() && workspace.active() is Some(_) &&
        !runtime.close_pending,
        runtime.ready() && !runtime.close_pending,
        action_presentation(workspace, runtime),
      )
    },
    state => {
      let (editor_enabled, search_enabled, actions) = state
      let editor = @semantics.node(tree, input).unwrap()
      if editor.enabled != editor_enabled {
        ignore(@semantics.set_enabled(tree, input, editor_enabled))
      }
      let search = @semantics.node(tree, search_input).unwrap()
      if search.enabled != search_enabled {
        ignore(@semantics.set_enabled(tree, search_input, search_enabled))
      }
      for index, action in actions {
        let reference = model.buttons[index]
        let node = @semantics.node(tree, reference).unwrap()
        if node.name != action.name {
          ignore(@semantics.set_name(tree, reference, action.name))
        }
        if node.enabled != action.enabled {
          ignore(@semantics.set_enabled(tree, reference, action.enabled))
        }
      }
    },
  )
  model.sync()
  {
    title: "Memo",
    editor: tree,
    default_input: Some(input),
    initial_size: model.size,
    viewport: Some({
      scroll: (x, y, pixels) => model.list.scroll_at(x, y, pixels),
      reveal: reference => model.list.reveal(reference),
    }),
    connect_tasks: control => {
      if tasks_connected.val {
        abort("Notes task control connected twice")
      }
      tasks_connected.val = true
      model.scope.on_dispose(() => {
        model.search.cancel_running(control)
        control.cancel(model.save_operation)
      })
    },
    initialize: () => model.load(),
    view: () => model.view(),
    activate: reference => model.activate(reference),
    resize: (width, height) => {
      if width < 320 || height < 360 || width > 2048 || height > 2048 {
        return false
      }
      let changed = model.size != (width, height)
      model.size = (width, height)
      changed
    },
    can_close: () => {
      model.persistence.state() != @persistence.Saving && !model.dirty()
    },
    close_requested: () => {
      if !model.close_pending {
        model.close_pending = true
        model.close_confirmed = model.persistence.state() == @persistence.Saving &&
          !model.save_waiting
        model.sync()
        ignore(@semantics.focus(tree, model.buttons[2]))
      }
    },
    close_ready: () => {
      model.close_pending &&
      model.close_confirmed &&
      model.persistence.state() == @persistence.Ready &&
      !model.dirty()
    },
    input_error: error => model.input_error = error,
    edited: edit => {
      if edit.target == model.search_input &&
        model.ready() &&
        !model.close_pending {
        let request = model.search.request(edit.text, () => {
          ignore(model.list.scroll(-2147483647))
          model.sync()
        })
        model.sync()
        return request
      }
      if edit.target != model.input ||
        !model.ready() ||
        model.close_pending ||
        !model.flush() {
        return None
      }
      model.sync()
      model.save(500)
    },
    stop: () => {
      model.search.close()
      model.persistence.close()
      model.scope.dispose()
      ignore(@semantics.dispose(tree))
    },
    dispose,
  }
}
