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
  status_value : @reactive.Signal[@component.StatusState]
  status : @component.UiStatus
  retry : @component.UiButton
  rotate : @component.UiButton
  theme_toggle : @component.UiButton
  disabled_button : @component.UiButton
  heading : @component.UiLabel
  single : @component.UiInput
  multi : @component.UiInput
  disabled_input : @component.UiInput
  single_value : @reactive.Signal[String]
  multi_value : @reactive.Signal[String]
  mut request_generation : Int
}

///|
fn alternate_theme() -> @theme.Theme {
  {
    ..@theme.default(),
    border: { red: b'\x63', green: b'\x45', blue: b'\x91', },
    focus: { red: b'\x15', green: b'\x80', blue: b'\x66', },
    status: { red: b'\xDC', green: b'\xF3', blue: b'\xE5', },
  }
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
  let status_value = @reactive.Signal::new(
    fixed.scope(),
    @component.StatusState::Waiting("Quote: waiting"),
  )
  let status = fixed
    .status("quote-status", @component.Read::new(() => status_value.peek()))
    .unwrap()
  let retry = fixed
    .button("retry", "Retry", () => {
      let gallery = self_ref.val.unwrap()
      gallery.request_generation += 1
      let generation = gallery.request_generation
      status_value.set(@component.StatusState::Loading("Quote: loading"))
      Some(
        @task.replace(() => (), () => {
          Some(
            @task.work(() => @async.sleep(120), _ => {
              if gallery.request_generation == generation &&
                !fixed.scope().is_disposed() {
                status_value.set(@component.StatusState::Ready("Quote: 112"))
                @task.Changed
              } else {
                @task.Unchanged
              }
            }),
          )
        }),
      )
    })
    .unwrap()
  let rotate = fixed
    .button("rotate", "Rotate rows", () => {
      let gallery = self_ref.val.unwrap()
      let rows = gallery.list_rows.copy()
      if !rows.is_empty() {
        let first = rows.remove(0)
        rows.push(first)
        ignore(gallery.set_list_rows(rows))
      }
      None
    })
    .unwrap()
  let theme_toggle = fixed
    .button("theme", "Switch theme", () => {
      let gallery = self_ref.val.unwrap()
      ignore(
        gallery.ui.set_theme(
          if gallery.ui.theme() == @theme.default() {
            alternate_theme()
          } else {
            @theme.default()
          },
        ),
      )
      None
    })
    .unwrap()
  let disabled_button = fixed
    .button(
      "disabled-button",
      "Disabled button",
      () => None,
      enabled=@component.Read::new(() => false),
    )
    .unwrap()
  let heading = fixed
    .label("heading", @component.Read::new(() => "Standard controls"))
    .unwrap()
  let single_value = @reactive.Signal::new(fixed.scope(), "Item key")
  let multi_value = @reactive.Signal::new(
    fixed.scope(),
    "First line\nSecond line",
  )
  let single = fixed
    .text_input(
      "single",
      "Single line",
      @component.Controlled::new(() => single_value.peek(), value => {
        single_value.set(value)
        None
      }),
    )
    .unwrap()
  let multi = fixed
    .text_area(
      "multi",
      "Multiple lines",
      @component.Controlled::new(() => multi_value.peek(), value => {
        multi_value.set(value)
        None
      }),
    )
    .unwrap()
  let disabled_input = fixed
    .text_input(
      "disabled-input",
      "Disabled input",
      @component.Controlled::new(() => "Unavailable", _ => None),
      enabled=@component.Read::new(() => false),
    )
    .unwrap()
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
    status_value,
    status,
    retry,
    rotate,
    theme_toggle,
    disabled_button,
    heading,
    single,
    multi,
    disabled_input,
    single_value,
    multi_value,
    request_generation: 0,
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
  let controls = @app.Stack::new(
      @layout.Vertical,
      gap=self.ui.theme().spacing.gap,
    )
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
  controls.push(
    @app.status(self.status, { x: 330, y: 370, width: 350, height: 40, }),
  )
  controls.push(
    @app.button(self.retry, { x: 330, y: 420, width: 150, height: 40, }),
  )
  controls.push(
    @app.button(self.disabled_button, {
      x: 500,
      y: 420,
      width: 180,
      height: 40,
    }),
  )
  controls.push(
    @app.button(self.rotate, { x: 330, y: 470, width: 150, height: 40, }),
  )
  controls.push(
    @app.button(self.theme_toggle, { x: 500, y: 470, width: 180, height: 40, }),
  )
  controls.push(
    @app.label(self.heading, { x: 330, y: 20, width: 350, height: 32, }),
  )
  controls.push(
    @app.input(self.single, { x: 330, y: 62, width: 350, height: 40, }),
  )
  controls.push(
    @app.input(self.multi, { x: 330, y: 112, width: 350, height: 96, }),
  )
  controls.push(
    @app.input(self.disabled_input, { x: 330, y: 224, width: 350, height: 40, }),
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
    initial_size: (720, 640),
    viewport: Some(gallery.list_view.viewport()),
    publications: None,
    downstreams: None,
    serials: None,
    components: Some(ui),
    connect_tasks: (_ : @task.TaskControl) => (),
    initialize: () => None,
    view: () => gallery.view(),
    activate: reference => ui.activate(reference),
    edited: edit => ui.edited(edit.target, edit.text, edit.revision),
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
