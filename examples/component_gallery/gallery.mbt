///|
pub struct Gallery {
  ui : @component.UiRoot
  checked : @component.UiCheckbox
  unchecked : @component.UiCheckbox
  disabled : @component.UiCheckbox
  invalid : @component.UiCheckbox
  toggle : @component.UiButton
  mut dynamic_owner : @component.UiOwner?
  mut dynamic : @component.UiCheckbox?
  list : @component.UiList[String]
  list_view : @app.ScrollView
  list_selection : @reactive.Signal[String?]
  mut list_rows : Array[@component.ListRow[String]]
}

///|
fn checked_control(
  owner : @component.UiOwner,
  key : String,
  label : String,
  initial : Bool,
  enabled? : Bool = true,
  invalid? : Bool = false,
) -> @component.UiCheckbox {
  let value = @reactive.Signal::new(owner.scope(), initial)
  owner
  .checkbox(
    key,
    label,
    @component.Controlled::new(() => value.peek(), checked => {
      value.set(checked)
      None
    }),
    enabled=@component.Read::new(() => enabled),
    invalid=@component.Read::new(() => invalid),
  )
  .unwrap()
}

///|
pub fn Gallery::new(ui : @component.UiRoot) -> Gallery {
  let fixed = ui.fixed("checkbox-gallery")
  let self_ref : Ref[Gallery?] = Ref(None)
  let toggle = fixed
    .button("dynamic-toggle", "Toggle dynamic", () => {
      self_ref.val.unwrap().toggle_dynamic()
      None
    })
    .unwrap()
  let list_selection = @reactive.Signal::new(fixed.scope(), Some("item-0"))
  let list = fixed.list("items", "Selectable items", list_selection).unwrap()
  let list_rows : Array[@component.ListRow[String]] = []
  for index in 0..<12 {
    list_rows.push({
      key: "item-" + index.to_string(),
      label: "Item " + index.to_string(),
      enabled: index != 4,
    })
  }
  ignore(list.reconcile(list_rows))
  let gallery : Gallery = {
    ui,
    checked: checked_control(fixed, "checked", "Checked", true),
    unchecked: checked_control(fixed, "unchecked", "Unchecked", false),
    disabled: checked_control(
      fixed,
      "disabled",
      "Disabled",
      false,
      enabled=false,
    ),
    invalid: checked_control(fixed, "invalid", "Error", false, invalid=true),
    toggle,
    dynamic_owner: None,
    dynamic: None,
    list,
    list_view: @app.ScrollView::new(gap=4).unwrap(),
    list_selection,
    list_rows,
  }
  self_ref.val = Some(gallery)
  gallery.toggle_dynamic()
  gallery
}

///|
pub fn Gallery::set_list_rows(
  self : Gallery,
  rows : Array[@component.ListRow[String]],
) -> Bool {
  self.list_rows = rows
  self.list.reconcile(rows)
}

///|
pub fn Gallery::toggle_dynamic(self : Gallery) -> Unit {
  if self.dynamic_owner is Some(owner) {
    owner.scope().dispose()
    self.dynamic_owner = None
    self.dynamic = None
  } else {
    let owner = self.ui.fixed("checkbox-gallery-dynamic")
    self.dynamic = Some(checked_control(owner, "dynamic", "Dynamic", false))
    self.dynamic_owner = Some(owner)
  }
}

///|
pub fn Gallery::view(self : Gallery) -> Array[@app.Control] {
  let items = [
    @app.StackItem::new(@layout.Fixed(40), @app.Widget::checkbox(self.checked)),
    @app.StackItem::new(
      @layout.Fixed(40),
      @app.Widget::checkbox(self.unchecked),
    ),
    @app.StackItem::new(@layout.Fixed(40), @app.Widget::checkbox(self.disabled)),
    @app.StackItem::new(@layout.Fixed(40), @app.Widget::checkbox(self.invalid)),
  ]
  if self.dynamic is Some(dynamic) {
    items.push(
      @app.StackItem::new(@layout.Fixed(40), @app.Widget::checkbox(dynamic)),
    )
  }
  items.push(
    @app.StackItem::new(@layout.Fixed(40), @app.Widget::button(self.toggle)),
  )
  let controls = @app.Stack::new(@layout.Vertical, gap=8)
    .arrange({ x: 20, y: 20, width: 280, height: 320, }, items)
    .unwrap()
  let bounds : @view.Bounds = { x: 20, y: 370, width: 280, height: 220, }
  controls.push(@app.list(self.list, bounds))
  controls.append(
    self.list_view
    .arrange(
      bounds,
      self.list
      .items()
      .map(item => @app.ScrollItem::new(36, @app.Widget::list_item(item))),
    )
    .unwrap(),
  )
  controls
}

///|
pub fn create() -> @app.Application {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(915, 1)
  let ui = @component.UiRoot::new(scope, tree)
  let gallery = Gallery::new(ui)
  {
    title: "Component gallery",
    editor: tree,
    default_input: None,
    initial_size: (400, 640),
    viewport: Some(gallery.list_view.viewport()),
    publications: None,
    downstreams: None,
    serials: None,
    components: Some(ui),
    connect_tasks: (_ : @task.TaskControl) => (),
    initialize: () => None,
    view: () => gallery.view(),
    activate: reference => ui.activate(reference),
    edited: _ => None,
    resize: (_, _) => true,
    stop: () => (),
    can_close: () => true,
    close_requested: () => (),
    close_ready: () => false,
    input_error: _ => (),
    dispose: () => {
      scope.dispose()
      ignore(@semantics.dispose(tree))
    },
  }
}
