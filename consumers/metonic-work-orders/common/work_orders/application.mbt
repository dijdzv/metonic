///|
pub(all) struct WorkOrder {
  id : String
  title : String
  details : String
  closed : Bool
} derive(Eq, Debug, ToJson, FromJson)

///|
fn seed_orders() -> Array[WorkOrder] {
  [
    {
      id: "WO-101",
      title: "Inspect entry light",
      details: "Check the switch and lamp.",
      closed: false,
    },
    {
      id: "WO-102",
      title: "Replace room filter",
      details: "Confirm the replacement size.",
      closed: false,
    },
    {
      id: "WO-103",
      title: "Verify exit sign",
      details: "Recorded after inspection.",
      closed: true,
    },
  ]
}

///|
fn selected_order(
  orders : @reactive.Signal[Array[WorkOrder]],
  selected : @reactive.Signal[String?],
) -> WorkOrder? {
  guard selected.get() is Some(id) else { return None }
  for order in orders.get() {
    if order.id == id {
      return Some(order)
    }
  }
  None
}

///|
fn reconcile_rows(
  list : @component.UiList[String],
  orders : @reactive.Signal[Array[WorkOrder]],
  query : @reactive.Signal[String],
  show_closed : @reactive.Signal[Bool],
) -> Unit {
  let rows : Array[@component.ListRow[String]] = []
  for order in orders.peek() {
    if (show_closed.peek() || !order.closed) &&
      (
        query.peek() == "" ||
        order.id.contains(query.peek()) ||
        order.title.contains(query.peek())
      ) {
      rows.push({
        key: order.id,
        label: order.id + "  " + order.title,
        enabled: true,
      })
    }
  }
  ignore(list.reconcile(rows))
}

///|
fn edit_selected(
  orders : @reactive.Signal[Array[WorkOrder]],
  selected : @reactive.Signal[String?],
  value : String,
  title : Bool,
) -> Bool {
  guard selected.peek() is Some(id) else { return false }
  let revised : Array[WorkOrder] = []
  let mut changed = false
  for order in orders.peek() {
    if order.id == id {
      if (if title { order.title } else { order.details }) != value {
        changed = true
        revised.push({
          id: order.id,
          title: if title {
            value
          } else {
            order.title
          },
          details: if title {
            order.details
          } else {
            value
          },
          closed: order.closed,
        })
      } else {
        revised.push(order)
      }
    } else {
      revised.push(order)
    }
  }
  if changed {
    orders.set(revised)
  }
  changed
}

///|
priv struct WorkOrdersUi {
  root : @reactive.Scope
  tree : @semantics.Tree
  list : @component.UiList[String]
  list_view : @app.ScrollView
  search : @component.UiInput
  show_closed : @component.UiCheckbox
  heading : @component.UiLabel
  title : @component.UiInput
  details : @component.UiInput
  status : @component.UiLabel
  save_button : @component.UiButton
  retry_button : @component.UiButton
  discard_button : @component.UiButton
  cancel_button : @component.UiButton
  persistence : Persistence
  mut size : (Int, Int)
}

///|
fn WorkOrdersUi::view(self : WorkOrdersUi) -> Array[@app.Control] {
  let left_width = 280
  let right_x = left_width + 40
  let right_width = (self.size.0 - right_x - 16).max(200)
  let list_bounds : @view.Bounds = {
    x: 16,
    y: 112,
    width: left_width,
    height: (self.size.1 - 128).max(160),
  }
  let controls : Array[@app.Control] = [
    @app.input(self.search, { x: 16, y: 16, width: left_width, height: 40, }),
    @app.checkbox(self.show_closed, {
      x: 16,
      y: 64,
      width: left_width,
      height: 36,
    }),
    @app.list(self.list, list_bounds),
    @app.label(self.heading, {
      x: right_x,
      y: 16,
      width: right_width,
      height: 32,
    }),
    @app.input(self.title, {
      x: right_x,
      y: 60,
      width: right_width,
      height: 40,
    }),
    @app.input(self.details, {
      x: right_x,
      y: 112,
      width: right_width,
      height: 190,
    }),
    @app.label(self.status, {
      x: right_x,
      y: 316,
      width: right_width,
      height: 36,
    }),
    @app.button(self.save_button, {
      x: right_x,
      y: 366,
      width: 160,
      height: 40,
    }),
  ]
  if self.persistence.can_retry_load() {
    controls.push(
      @app.button(self.retry_button, {
        x: right_x + 172,
        y: 366,
        width: 148,
        height: 40,
      }),
    )
  }
  if self.persistence.close_pending {
    let action_width = (right_width - 12) / 2
    controls.push(
      @app.button(self.discard_button, {
        x: right_x,
        y: 416,
        width: action_width,
        height: 40,
      }),
    )
    controls.push(
      @app.button(self.cancel_button, {
        x: right_x + action_width + 12,
        y: 416,
        width: action_width,
        height: 40,
      }),
    )
  }
  controls.append(
    self.list_view
    .arrange(
      list_bounds,
      self.list
      .items()
      .map(item => @app.ScrollItem::new(38, @app.Widget::list_item(item))),
    )
    .unwrap(),
  )
  controls
}

///|
pub fn create(
  snapshot : @snapshot.Snapshot,
  dispose_storage : async () -> Unit,
) -> @app.Application {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let document = root.child()
  let persistence = Persistence::new(root, snapshot)
  let orders : @reactive.Signal[Array[WorkOrder]] = @reactive.Signal::new(
    document,
    [],
  )
  let selected : @reactive.Signal[String?] = @reactive.Signal::new(
    document,
    None,
  )
  let show_closed = @reactive.Signal::new(root, false)
  let tree = @semantics.empty(91, 1)
  let ui = @component.UiRoot::new(root, tree)
  let filters = ui.fixed("filters")
  let query = @reactive.Signal::new(filters.scope(), "")
  let list = filters.list("orders", "Work orders", selected).unwrap()
  reconcile_rows(list, orders, query, show_closed)
  let apply_loaded = (loaded : Array[WorkOrder]) => {
    root
    .graph()
    .batch(() => {
      orders.set(loaded)
      selected.set(if loaded.length() > 0 { Some(loaded[0].id) } else { None })
      reconcile_rows(list, orders, query, show_closed)
    })
  }
  let search = filters
    .text_input(
      "search",
      "Search work orders",
      @component.Controlled::new(() => query.get(), text => {
        query.set(text)
        reconcile_rows(list, orders, query, show_closed)
        None
      }),
    )
    .unwrap()
  let show_closed_input = filters
    .checkbox(
      "show-closed",
      "Show closed",
      @component.Controlled::new(() => show_closed.get(), value => {
        show_closed.set(value)
        reconcile_rows(list, orders, query, show_closed)
        None
      }),
    )
    .unwrap()
  let detail_owner = ui.fixed("detail")
  let heading = detail_owner
    .label(
      "heading",
      @component.Read::new(() => {
        match selected_order(orders, selected) {
          Some(order) => order.id
          None => "Select a work order"
        }
      }),
    )
    .unwrap()
  let title = detail_owner
    .text_input(
      "title",
      "Title",
      @component.Controlled::new(
        () => {
          selected_order(orders, selected)
          .map(order => order.title)
          .unwrap_or("")
        },
        value => {
          guard persistence.can_edit() else { return None }
          guard value.length() <= 1024 else {
            persistence.reject_edit("Title exceeds the editor limit")
            return None
          }
          if edit_selected(orders, selected, value, true) {
            persistence.edited()
            reconcile_rows(list, orders, query, show_closed)
          }
          None
        },
      ),
      enabled=@component.Read::new(() => {
        ignore(persistence.status())
        persistence.can_edit() && selected.peek() is Some(_)
      }),
    )
    .unwrap()
  let details = detail_owner
    .text_area(
      "details",
      "Details",
      @component.Controlled::new(
        () => {
          selected_order(orders, selected)
          .map(order => order.details)
          .unwrap_or("")
        },
        value => {
          guard persistence.can_edit() else { return None }
          guard value.length() <= 1024 else {
            persistence.reject_edit("Details exceed the editor limit")
            return None
          }
          if edit_selected(orders, selected, value, false) {
            persistence.edited()
          }
          None
        },
      ),
      enabled=@component.Read::new(() => {
        ignore(persistence.status())
        persistence.can_edit() && selected.peek() is Some(_)
      }),
    )
    .unwrap()
  let actions = ui.fixed("storage-actions")
  let status = actions
    .label("status", @component.Read::new(() => persistence.status()))
    .unwrap()
  let save_button = actions
    .button(
      "save",
      "Save",
      () => persistence.save(orders.peek()),
      enabled=@component.Read::new(() => {
        ignore(persistence.status())
        persistence.can_save()
      }),
    )
    .unwrap()
  let retry_button = actions
    .button(
      "retry-load",
      "Retry load",
      () => persistence.load(apply_loaded),
      enabled=@component.Read::new(() => {
        ignore(persistence.status())
        persistence.can_retry_load()
      }),
    )
    .unwrap()
  let discard_button = actions
    .button(
      "discard-close",
      "Discard",
      () => {
        persistence.discard_and_close()
        None
      },
      enabled=@component.Read::new(() => {
        ignore(persistence.status())
        persistence.close_pending && !persistence.saving
      }),
    )
    .unwrap()
  let cancel_button = actions
    .button(
      "cancel-close",
      "Keep editing",
      () => {
        persistence.cancel_close()
        None
      },
      enabled=@component.Read::new(() => {
        ignore(persistence.status())
        persistence.close_pending
      }),
    )
    .unwrap()
  let screen : WorkOrdersUi = {
    root,
    tree,
    list,
    list_view: @app.ScrollView::new(gap=2).unwrap(),
    search,
    show_closed: show_closed_input,
    heading,
    title,
    details,
    status,
    save_button,
    retry_button,
    discard_button,
    cancel_button,
    persistence,
    size: (800, 520),
  }
  {
    title: "Work orders",
    editor: tree,
    default_input: Some(search.reference()),
    initial_size: screen.size,
    viewport: Some(screen.list_view.viewport()),
    publications: None,
    downstreams: None,
    serials: None,
    components: Some(ui),
    connect_tasks: control => persistence.connect(control),
    initialize: () => persistence.load(apply_loaded),
    view: () => screen.view(),
    activate: reference => ui.activate(reference),
    edited: edit => ui.edited(edit.target, edit.text, edit.revision),
    resize: (width, height) => {
      if width < 700 || height < 500 {
        return false
      }
      let changed = screen.size != (width, height)
      screen.size = (width, height)
      changed
    },
    stop: () => (),
    can_close: () => screen.persistence.can_close(),
    close_requested: () => screen.persistence.request_close(),
    close_ready: () => screen.persistence.close_ready(),
    input_error: _ => (),
    dispose: () => {
      screen.root.dispose()
      ignore(@semantics.dispose(screen.tree))
      dispose_storage()
    },
  }
}
