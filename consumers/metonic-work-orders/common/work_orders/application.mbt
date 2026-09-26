///|
pub(all) struct WorkOrder {
  id : String
  title : String
  details : String
  closed : Bool
} derive(Eq)

///|
fn seed_orders() -> Array[WorkOrder] {
  [
    { id: "WO-101", title: "Inspect entry light", details: "Check the switch and lamp.", closed: false, },
    { id: "WO-102", title: "Replace room filter", details: "Confirm the replacement size.", closed: false, },
    { id: "WO-103", title: "Verify exit sign", details: "Recorded after inspection.", closed: true, },
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
      (query.peek() == "" || order.id.contains(query.peek()) ||
      order.title.contains(query.peek())) {
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
) -> Unit {
  guard selected.peek() is Some(id) else { return }
  let revised : Array[WorkOrder] = []
  for order in orders.peek() {
    if order.id == id {
      revised.push({
        id: order.id,
        title: if title { value } else { order.title },
        details: if title { order.details } else { value },
        closed: order.closed,
      })
    } else {
      revised.push(order)
    }
  }
  orders.set(revised)
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
    @app.checkbox(self.show_closed, { x: 16, y: 64, width: left_width, height: 36, }),
    @app.list(self.list, list_bounds),
    @app.label(self.heading, { x: right_x, y: 16, width: right_width, height: 32, }),
    @app.input(self.title, { x: right_x, y: 60, width: right_width, height: 40, }),
    @app.input(self.details, { x: right_x, y: 112, width: right_width, height: 210, }),
  ]
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
pub fn create() -> @app.Application {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let document = root.child()
  let orders = @reactive.Signal::new(document, seed_orders())
  let selected = @reactive.Signal::new(document, Some("WO-101"))
  let show_closed = @reactive.Signal::new(root, false)
  let tree = @semantics.empty(91, 1)
  let ui = @component.UiRoot::new(root, tree)
  let filters = ui.fixed("filters")
  let query = @reactive.Signal::new(filters.scope(), "")
  let list = filters.list("orders", "Work orders", selected).unwrap()
  reconcile_rows(list, orders, query, show_closed)
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
      @component.Read::new(() => match selected_order(orders, selected) {
        Some(order) => order.id
        None => "Select a work order"
      }),
    )
    .unwrap()
  let title = detail_owner
    .text_input(
      "title",
      "Title",
      @component.Controlled::new(
        () => selected_order(orders, selected).map(order => order.title).unwrap_or(""),
        value => {
          edit_selected(orders, selected, value, true)
          reconcile_rows(list, orders, query, show_closed)
          None
        },
      ),
      enabled=@component.Read::new(() => selected.peek() is Some(_)),
    )
    .unwrap()
  let details = detail_owner
    .text_area(
      "details",
      "Details",
      @component.Controlled::new(
        () => selected_order(orders, selected).map(order => order.details).unwrap_or(""),
        value => {
          edit_selected(orders, selected, value, false)
          None
        },
      ),
      enabled=@component.Read::new(() => selected.peek() is Some(_)),
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
    size: (800, 500),
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
    connect_tasks: (_ : @task.TaskControl) => (),
    initialize: () => None,
    view: () => screen.view(),
    activate: reference => ui.activate(reference),
    edited: edit => ui.edited(edit.target, edit.text, edit.revision),
    resize: (width, height) => {
      if width < 600 || height < 350 {
        return false
      }
      let changed = screen.size != (width, height)
      screen.size = (width, height)
      changed
    },
    stop: () => (),
    can_close: () => true,
    close_requested: () => (),
    close_ready: () => false,
    input_error: _ => (),
    dispose: () => {
      screen.root.dispose()
      ignore(@semantics.dispose(screen.tree))
    },
  }
}
