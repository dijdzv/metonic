///|
struct ItemPair {
  name : String
  stock : Int
} derive(Eq)

///|
struct QuoteInput {
  name : String
  stock : Int
  quantity : Int
} derive(Eq)

///|
struct Quote {
  name : String
  stock : Int
  quantity : Int
  shipping : Int
} derive(Eq)

///|
struct DisplayQuote {
  quote : Quote
  currency : String
  amount : Int
} derive(Eq)

///|
fn DisplayQuote::amount_text(self : DisplayQuote) -> String {
  self.amount.to_string() +
  (if self.currency == "JPY" { "" } else { " " + self.currency })
}

///|
priv struct Board {
  graph : @reactive.Graph
  scope : @reactive.Scope
  selected : @reactive.Signal[String]
  quantity : @reactive.Signal[Int]
  currency : @reactive.Signal[String]
  rate_cycle : @reactive.Signal[@async_state.Cycle]
  rate : @async_state.Source[String, Int]
  items : @component.KeyedChildren[String, Unit, ItemChild]
  downstreams : @async_state.DownstreamRegistry
  publications : @async_state.PublicationRegistry
  note : Note
  tree : @semantics.Tree
  ui : @component.UiRoot
  mut buttons : Array[@component.UiButton]
  mut heading_label : @component.UiLabel?
  mut detail_status : @component.UiStatus?
  mut stock_status : @component.UiStatus?
  mut quote_status : @component.UiStatus?
  wait : async (Int) -> Unit
  rate_result : (String) -> Result[Int, String]
  quote_result : (QuoteInput) -> Result[Int, String]
  diagnostics : @async_state.TraceRegistry?
  trace_owner : Int?
  mut task_control : @task.TaskControl?
  mut size : (Int, Int)
  mut error : String?
}

///|
priv struct ItemChild {
  key : String
  trace_owner : Int?
  cycle : @reactive.Signal[@async_state.Cycle]
  detail : @async_state.Source[String, String]
  stock : @async_state.Source[String, Int]
  details : @component.KeyedChildren[String, Unit, DetailChild]
}

///|
priv struct DetailChild {
  quote : @async_state.Downstream[QuoteInput, Quote]
  display : @async_state.Publication[(String, Int, String), DisplayQuote]
  quantity_button : @component.UiButton
  retry_button : @component.UiButton
}

///|
fn Board::new_item(
  self : Board,
  owner : @component.ChildOwner,
  key : String,
) -> ItemChild {
  let detail : @async_state.Source[String, String] = @async_state.Source::new(
    owner.scope(),
  )
  let stock : @async_state.Source[String, Int] = @async_state.Source::new(
    owner.scope(),
  )
  guard self.task_control is Some(control) &&
    detail.connect(control) &&
    stock.connect(control) else {
    abort("quote board item Sources could not connect")
  }
  let item : ItemChild = {
    key,
    trace_owner: if self.diagnostics is Some(registry) {
      let owner_id = registry
        .track_owner(
          owner.scope(),
          self.trace_owner,
          @async_state.ComponentOwner,
          owner.generation(),
        )
        .unwrap()
      let key_id = key => if key == "amber" { 1 } else { 2 }
      if !registry.track_source(detail, owner_id, key_id) ||
        !registry.track_source(stock, owner_id, key_id) {
        abort("quote board item diagnostics registration failed")
      }
      Some(owner_id)
    } else {
      None
    },
    cycle: @reactive.Signal::new(owner.scope(), @async_state.Cycle::new()),
    detail,
    stock,
    details: @component.KeyedChildren::new(owner.scope(), self.tree),
  }
  ignore(item.show_detail(self))
  item
}

///|
fn ItemChild::show_detail(self : ItemChild, board : Board) -> Bool {
  self.details.reconcile(
    [{ key: "detail", props: (), }],
    (owner, _, _) => {
      let quote = board.downstreams.register_result(
        owner.scope(),
        () => {
          let related = @async_state.Related::new(self.key, self.cycle.get())
          @async_state.join_related(
            related.read(self.detail),
            related.read(self.stock),
            fn(name, amount) { ItemPair::{ name, stock: amount, } },
          )
          .current()
          .map(pair => QuoteInput::{
            name: pair.name,
            stock: pair.stock,
            quantity: board.quantity.get(),
          })
        },
        input => {
          (board.wait)(250)
          match (board.quote_result)(input) {
            Ok(shipping) =>
              Ok(Quote::{
                name: input.name,
                stock: input.stock,
                quantity: input.quantity,
                shipping,
              })
            Err(message) => Err(message)
          }
        },
        error => error,
      )
      if board.diagnostics is Some(registry) {
        let owner_id = registry
          .track_owner(
            owner.scope(),
            self.trace_owner,
            @async_state.ComponentOwner,
            owner.generation(),
          )
          .unwrap()
        if !quote.track_source(registry, owner_id, input => {
            input.quantity * 2 + (if self.key == "amber" { 1 } else { 0 })
          }) ||
          !registry.track_derived(owner.scope(), owner_id, owner_id, () => {
            quote.current()
          }) {
          abort("quote board downstream diagnostics registration failed")
        }
      }
      let display = board.publications.register(owner.scope(), () => {
        let currency = board.currency.get()
        let current = quote.current()
        let converted = if currency == "JPY" {
          current.map(value => DisplayQuote::{
            quote: value,
            currency,
            amount: value.shipping,
          })
        } else {
          @async_state.join_independent(
            current,
            board.rate.current(currency, board.rate_cycle.get()),
            fn(value, rate) {
              DisplayQuote::{
                quote: value,
                currency,
                amount: value.shipping * rate,
              }
            },
          )
        }
        ((self.key, board.quantity.get(), currency), converted)
      })
      let controls = board.ui.adopt(owner)
      let quantity_button = controls
        .button("quantity", "Quantity +", () => {
          board.quantity.set(board.quantity.peek() + 1)
          None
        })
        .unwrap()
      let retry_button = controls
        .button("retry", "Retry quote", () => {
          ignore(quote.retry())
          None
        })
        .unwrap()
      DetailChild::{ quote, display, quantity_button, retry_button, }
    },
    (_, _) => (),
  )
}

///|
fn Board::choose_currency(self : Board, currency : String) -> @task.Request? {
  self.currency.set(currency)
  if currency == "JPY" {
    ignore(self.rate.retire_current())
    return None
  }
  let cycle = @async_state.Cycle::new()
  let rate = self.rate.replace_result(
    currency,
    cycle,
    false,
    () => {
      (self.wait)(600)
      (self.rate_result)(currency)
    },
    error => error,
  )
  guard rate is Some(request) else { return None }
  Some(
    @task.group([request], apply => self.graph.batch(apply), on_admitted=() => {
      self.rate_cycle.set(cycle)
    }),
  )
}

///|
fn Board::request(
  self : Board,
  item : String,
  retain_previous : Bool,
) -> @task.Request? {
  ignore(
    self.items.reconcile(
      [{ key: item, props: (), }],
      (owner, key, _) => self.new_item(owner, key),
      (_, _) => (),
    ),
  )
  self.selected.set(item)
  let child = self.items.get(item).unwrap()
  let cycle = @async_state.Cycle::new()
  let detail_delay = if item == "amber" { 900 } else { 200 }
  let stock_delay = if item == "amber" { 200 } else { 900 }
  let detail = child.detail.replace(item, cycle, retain_previous, () => {
    (self.wait)(detail_delay)
    if item == "amber" {
      "Amber lamp"
    } else {
      "Blue stool"
    }
  })
  let stock = child.stock.replace(item, cycle, retain_previous, () => {
    (self.wait)(stock_delay)
    if item == "amber" {
      12
    } else {
      7
    }
  })
  guard (detail, stock) is (Some(detail), Some(stock)) else { return None }
  Some(
    @task.group([detail, stock], apply => self.graph.batch(apply), on_admitted=() => {
      child.cycle.set(cycle)
    }),
  )
}

///|
fn Board::heading(self : Board) -> String {
  "Item: " +
  self.selected.peek() +
  " · Quantity: " +
  self.quantity.peek().to_string() +
  " · Currency: " +
  self.currency.peek()
}

///|
fn Board::detail_state(self : Board) -> @component.StatusState {
  guard self.items.get(self.selected.peek()) is Some(child) else {
    return @component.Waiting("Detail: waiting")
  }
  match child.detail.current(self.selected.peek(), child.cycle.peek()).view() {
    CurrentReady(name, _) => @component.Ready("Detail: " + name)
    CurrentPending(_) => @component.Loading("Detail: loading")
    CurrentFailed(_) => @component.Failed("Detail: failed")
    CurrentCanceled(_) => @component.Canceled("Detail: canceled")
    _ => @component.Waiting("Detail: waiting")
  }
}

///|
fn Board::stock_state(self : Board) -> @component.StatusState {
  guard self.items.get(self.selected.peek()) is Some(child) else {
    return @component.Waiting("Stock: waiting")
  }
  match child.stock.current(self.selected.peek(), child.cycle.peek()).view() {
    CurrentReady(amount, _) => @component.Ready("Stock: " + amount.to_string())
    CurrentPending(_) => @component.Loading("Stock: loading")
    CurrentFailed(_) => @component.Failed("Stock: failed")
    CurrentCanceled(_) => @component.Canceled("Stock: canceled")
    _ => @component.Waiting("Stock: waiting")
  }
}

///|
fn Board::quote_state(self : Board) -> @component.StatusState {
  let item = self.selected.peek()
  guard self.items.get(item) is Some(child) else {
    return @component.Waiting("Shipping: waiting for item")
  }
  guard child.details.get("detail") is Some(details) else {
    return @component.Waiting("Shipping: detail hidden")
  }
  match details.display.get() {
    Some({ current: CurrentReady(value, _), .. }) =>
      @component.Ready(
        "Shipping: " +
        value.amount_text() +
        " for " +
        value.quote.quantity.to_string(),
      )
    Some({ current: CurrentPending(_), previous: Some(previous), .. })
    | Some({ current: CurrentBlocked(_), previous: Some(previous), .. }) =>
      @component.RetainedPrevious(
        "Shipping: loading",
        previous.value.amount_text(),
      )
    Some({ current: CurrentPending(_), .. }) =>
      @component.Loading("Shipping: loading")
    Some({ current: CurrentCanceled(_), .. }) =>
      @component.Canceled("Shipping: canceled")
    Some({ current: CurrentFailed(_), .. }) =>
      if details.quote.current().view() is CurrentFailed(_) {
        @component.Failed(
          "Shipping: failed for " +
          item +
          " x" +
          self.quantity.peek().to_string(),
        )
      } else if details.quote.admission() is @async_state.Rejected(_, _) {
        @component.Rejected("Shipping: failed")
      } else {
        @component.Failed("Shipping: failed")
      }
    _ => @component.Waiting("Shipping: waiting for item")
  }
}

///|
fn Board::view(self : Board) -> Array[@app.Control] {
  let controls : Array[@app.Control] = []
  let first_row : Array[@app.StackItem] = []
  let second_row : Array[@app.StackItem] = []
  for index, button in self.buttons {
    let item = @app.StackItem::new(
      @layout.Fixed(128),
      @app.Widget::button(button),
    )
    if index < 4 {
      first_row.push(item)
    } else {
      second_row.push(item)
    }
  }
  if self.items.get(self.selected.peek()) is Some(child) {
    match child.details.get("detail") {
      Some(details) => {
        first_row.push(
          @app.StackItem::new(
            @layout.Fixed(128),
            @app.Widget::button(details.quantity_button),
          ),
        )
        if details.quote.current().view() is CurrentFailed(_) ||
          details.quote.admission() is @async_state.Rejected(_, _) {
          second_row.push(
            @app.StackItem::new(
              @layout.Fixed(128),
              @app.Widget::button(details.retry_button),
            ),
          )
        }
      }
      None => ()
    }
  }
  let button_row = @app.Stack::new(@layout.Horizontal, gap=10)
  let arranged_first = button_row
    .arrange({ x: 16, y: 16, width: 680, height: 36, }, first_row)
    .unwrap()
  let arranged_second = button_row
    .arrange({ x: 16, y: 58, width: 680, height: 36, }, second_row)
    .unwrap()
  for control in arranged_first {
    controls.push(control)
  }
  for control in arranged_second {
    controls.push(control)
  }
  for index in 0..<4 {
    let bounds : @view.Bounds = {
      x: 16,
      y: 112 + index * 48,
      width: (self.size.0 - 32).max(32),
      height: 42,
    }
    if index == 0 {
      controls.push(@app.label(self.heading_label.unwrap(), bounds))
    } else {
      let widget = match index {
        1 => self.detail_status.unwrap()
        2 => self.stock_status.unwrap()
        _ => self.quote_status.unwrap()
      }
      controls.push(@app.status(widget, bounds))
    }
  }
  controls.push(
    @app.input(self.note.input, {
      x: 16,
      y: 320,
      width: (self.size.0 - 172).max(32),
      height: 72,
    }),
  )
  controls.push({
    element: {
      bounds: { x: self.size.0 - 144, y: 320, width: 128, height: 36, },
      text: "Save note",
      reference: Some(self.note.save_button),
      focused: @semantics.node(self.tree, self.note.save_button).unwrap().focused,
    },
    kind: @app.Button,
    clip: None,
  })
  controls.push({
    element: {
      bounds: { x: 16, y: 400, width: (self.size.0 - 32).max(32), height: 36, },
      text: self.note.status(),
      reference: None,
      focused: false,
    },
    kind: @app.Text,
    clip: None,
  })
  if self.error is Some(message) {
    controls.push({
      element: {
        bounds: {
          x: 16,
          y: 444,
          width: (self.size.0 - 32).max(32),
          height: 40,
        },
        text: message,
        reference: None,
        focused: false,
      },
      kind: @app.Text,
      clip: None,
    })
  }
  controls
}

///|
pub fn create_with_rate(
  wait : async (Int) -> Unit,
  rate_result : (String) -> Result[Int, String],
  diagnostics? : @async_state.TraceRegistry? = None,
) -> @app.Application {
  let stored : Ref[SaveSnapshot?] = Ref(None)
  create_with_save(
    wait,
    rate_result,
    snapshot => {
      wait(800)
      stored.val = Some(snapshot)
      Ok(())
    },
    diagnostics~,
  )
}

///|
pub fn create_with_save(
  wait : async (Int) -> Unit,
  rate_result : (String) -> Result[Int, String],
  save : async (SaveSnapshot) -> Result[Unit, String],
  diagnostics? : @async_state.TraceRegistry? = None,
) -> @app.Application {
  let failed_once = Ref(false)
  create_with_quote_result(
    wait,
    rate_result,
    save,
    (name, stock, quantity) => {
      if name == "Blue stool" && quantity == 4 && !failed_once.val {
        failed_once.val = true
        Err("quote service unavailable")
      } else {
        Ok((100 + stock) * quantity)
      }
    },
    diagnostics~,
  )
}

///|
pub fn create_with_quote_result(
  wait : async (Int) -> Unit,
  rate_result : (String) -> Result[Int, String],
  save : async (SaveSnapshot) -> Result[Unit, String],
  quote_result : (String, Int, Int) -> Result[Int, String],
  diagnostics? : @async_state.TraceRegistry? = None,
) -> @app.Application {
  let graph = @reactive.Graph::new()
  let scope = @reactive.Scope::root(graph)
  let selected = @reactive.Signal::new(scope, "amber")
  let quantity = @reactive.Signal::new(scope, 1)
  let currency = @reactive.Signal::new(scope, "JPY")
  let rate_cycle = @reactive.Signal::new(scope, @async_state.Cycle::new())
  let rate : @async_state.Source[String, Int] = @async_state.Source::new(scope)
  let trace_owner = if diagnostics is Some(registry) {
    let owner_id = registry
      .track_owner(scope, None, @async_state.ApplicationOwner, 0)
      .unwrap()
    if !registry.track_source(rate, owner_id, key => {
        if key == "USD" {
          1
        } else {
          2
        }
      }) {
      abort("quote board currency diagnostics registration failed")
    }
    Some(owner_id)
  } else {
    None
  }
  let downstreams = @async_state.DownstreamRegistry::new(scope)
  let publications = @async_state.PublicationRegistry::new(scope)
  let serials = @async_state.SerialRegistry::new(scope)
  let tree = @semantics.empty(1, 1)
  let ui = @component.UiRoot::new(scope, tree)
  let note = Note::new(scope, tree, ui, serials, save)
  let items : @component.KeyedChildren[String, Unit, ItemChild] = @component.KeyedChildren::new(
    scope, tree,
  )
  let model : Board = {
    graph,
    scope,
    selected,
    quantity,
    currency,
    rate_cycle,
    rate,
    items,
    downstreams,
    publications,
    note,
    tree,
    ui,
    buttons: [],
    heading_label: None,
    detail_status: None,
    stock_status: None,
    quote_status: None,
    wait,
    rate_result,
    quote_result: input => quote_result(input.name, input.stock, input.quantity),
    diagnostics,
    trace_owner,
    task_control: None,
    size: (720, 500),
    error: None,
  }
  let actions = ui.fixed("actions")
  let summary = ui.fixed("summary")
  model.heading_label = summary.label(
    "heading",
    @component.Read::new(() => model.heading()),
  )
  model.detail_status = summary.status(
    "detail",
    @component.Read::new(() => model.detail_state()),
  )
  model.stock_status = summary.status(
    "stock",
    @component.Read::new(() => model.stock_state()),
  )
  model.quote_status = summary.status(
    "quote",
    @component.Read::new(() => model.quote_state()),
  )
  model.buttons = [
    actions
    .button("amber", "Amber lamp", () => model.request("amber", false))
    .unwrap(),
    actions
    .button("blue", "Blue stool", () => model.request("blue", false))
    .unwrap(),
    actions
    .button("refresh", "Refresh", () => {
      model.request(model.selected.peek(), true)
    })
    .unwrap(),
    actions
    .button("detail", "Toggle detail", () => {
      if model.items.get(model.selected.peek()) is Some(item) {
        if item.details.get("detail") is Some(_) {
          ignore(item.details.clear())
        } else {
          ignore(item.show_detail(model))
        }
      }
      None
    })
    .unwrap(),
    actions.button("jpy", "JPY", () => model.choose_currency("JPY")).unwrap(),
    actions.button("usd", "USD", () => model.choose_currency("USD")).unwrap(),
  ]
  {
    title: "Item and quote board",
    editor: tree,
    default_input: Some(note.input.reference()),
    initial_size: model.size,
    viewport: None,
    publications: Some(publications),
    downstreams: Some(downstreams),
    serials: Some(serials),
    components: Some(ui),
    connect_tasks: control => {
      if !downstreams.connect(control) ||
        !rate.connect(control) ||
        !serials.connect(control) {
        abort("quote board task connection failed")
      }
      model.task_control = Some(control)
    },
    initialize: () => model.request("amber", false),
    view: () => model.view(),
    activate: reference => {
      if reference == model.note.save_button {
        ignore(model.note.save())
        None
      } else {
        ui.activate(reference)
      }
    },
    edited: edit => ui.edited(edit.target, edit.text, edit.revision),
    resize: (width, height) => {
      if width < 700 || height < 480 {
        return false
      }
      let changed = model.size != (width, height)
      model.size = (width, height)
      changed
    },
    stop: () => (),
    can_close: () => model.note.can_close(),
    close_requested: () => model.note.request_close(),
    close_ready: () => model.note.close_ready(),
    input_error: message => model.error = message,
    dispose: () => model.scope.dispose(),
  }
}

///|
pub fn create(
  wait : async (Int) -> Unit,
  diagnostics? : @async_state.TraceRegistry? = None,
) -> @app.Application {
  create_with_rate(wait, _ => Ok(2), diagnostics~)
}
