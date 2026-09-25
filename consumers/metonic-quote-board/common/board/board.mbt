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
  buttons : Array[@semantics.NodeRef]
  wait : async (Int) -> Unit
  rate_result : (String) -> Result[Int, String]
  mut task_control : @task.TaskControl?
  mut size : (Int, Int)
  mut error : String?
}

///|
priv struct ItemChild {
  key : String
  cycle : @reactive.Signal[@async_state.Cycle]
  detail : @async_state.Source[String, String]
  stock : @async_state.Source[String, Int]
  details : @component.KeyedChildren[String, Unit, DetailChild]
}

///|
priv struct DetailChild {
  display : @async_state.Publication[(String, Int, String), DisplayQuote]
  quantity_button : @semantics.NodeRef
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
      let quote = board.downstreams.register(
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
          {
            name: input.name,
            stock: input.stock,
            quantity: input.quantity,
            shipping: (100 + input.stock) * input.quantity,
          }
        },
      )
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
      let quantity_button = owner.add_button("Quantity +").unwrap()
      DetailChild::{ display, quantity_button, }
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
fn Board::view(self : Board) -> Array[@app.Control] {
  let controls : Array[@app.Control] = []
  let names = [
    "Amber lamp", "Blue stool", "Refresh", "Toggle detail", "JPY", "USD",
  ]
  for index, reference in self.buttons {
    let node = @semantics.node(self.tree, reference).unwrap()
    controls.push({
      element: {
        bounds: {
          x: if index < 4 {
            16 + index * 138
          } else {
            16 + (index - 4) * 138
          },
          y: if index < 4 {
            16
          } else {
            58
          },
          width: 128,
          height: 36,
        },
        text: names[index],
        reference: Some(reference),
        focused: node.focused,
      },
      kind: @app.Button,
      clip: None,
    })
  }
  let item = self.selected.peek()
  let mut detail = "Detail: waiting"
  let mut stock = "Stock: waiting"
  let mut quote = "Shipping: waiting for item"
  if self.items.get(item) is Some(child) {
    let cycle = child.cycle.peek()
    detail = match child.detail.current(item, cycle).view() {
      CurrentReady(name, _) => "Detail: " + name
      CurrentPending(_) => "Detail: loading"
      CurrentFailed(_) => "Detail: failed"
      _ => "Detail: waiting"
    }
    stock = match child.stock.current(item, cycle).view() {
      CurrentReady(amount, _) => "Stock: " + amount.to_string()
      CurrentPending(_) => "Stock: loading"
      CurrentFailed(_) => "Stock: failed"
      _ => "Stock: waiting"
    }
    match child.details.get("detail") {
      Some(details) => {
        let node = @semantics.node(self.tree, details.quantity_button).unwrap()
        controls.push({
          element: {
            bounds: { x: 16 + 4 * 138, y: 16, width: 128, height: 36, },
            text: "Quantity +",
            reference: Some(details.quantity_button),
            focused: node.focused,
          },
          kind: @app.Button,
          clip: None,
        })
        quote = match details.display.get() {
          Some({ current: CurrentReady(value, _), .. }) =>
            "Shipping: " +
            value.amount_text() +
            " for " +
            value.quote.quantity.to_string()
          Some({ current: CurrentPending(_), previous: Some(previous), .. }) =>
            "Shipping: loading (previous " + previous.value.amount_text() + ")"
          Some({ current: CurrentBlocked(_), previous: Some(previous), .. }) =>
            "Shipping: loading (previous " + previous.value.amount_text() + ")"
          Some({ current: CurrentPending(_), .. }) => "Shipping: loading"
          Some({ current: CurrentFailed(_), .. }) => "Shipping: failed"
          _ => "Shipping: waiting for item"
        }
      }
      None => quote = "Shipping: detail hidden"
    }
  }
  let lines = [
    "Item: " +
    item +
    " · Quantity: " +
    self.quantity.peek().to_string() +
    " · Currency: " +
    self.currency.peek(),
    detail,
    stock,
    quote,
  ]
  for index, line in lines {
    controls.push({
      element: {
        bounds: {
          x: 16,
          y: 112 + index * 48,
          width: (self.size.0 - 32).max(32),
          height: 42,
        },
        text: line,
        reference: None,
        focused: false,
      },
      kind: @app.Text,
      clip: None,
    })
  }
  let note_node = @semantics.node(self.tree, self.note.input).unwrap()
  controls.push({
    element: {
      bounds: { x: 16, y: 320, width: (self.size.0 - 172).max(32), height: 72, },
      text: note_node.value,
      reference: Some(self.note.input),
      focused: note_node.focused,
    },
    kind: @app.Input(single_line=false),
    clip: None,
  })
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
) -> @app.Application {
  let stored : Ref[SaveSnapshot?] = Ref(None)
  create_with_save(wait, rate_result, snapshot => {
    wait(800)
    stored.val = Some(snapshot)
    Ok(())
  })
}

///|
pub fn create_with_save(
  wait : async (Int) -> Unit,
  rate_result : (String) -> Result[Int, String],
  save : async (SaveSnapshot) -> Result[Unit, String],
) -> @app.Application {
  let graph = @reactive.Graph::new()
  let scope = @reactive.Scope::root(graph)
  let selected = @reactive.Signal::new(scope, "amber")
  let quantity = @reactive.Signal::new(scope, 1)
  let currency = @reactive.Signal::new(scope, "JPY")
  let rate_cycle = @reactive.Signal::new(scope, @async_state.Cycle::new())
  let rate : @async_state.Source[String, Int] = @async_state.Source::new(scope)
  let downstreams = @async_state.DownstreamRegistry::new(scope)
  let publications = @async_state.PublicationRegistry::new(scope)
  let serials = @async_state.SerialRegistry::new(scope)
  let tree = @semantics.empty(1, 1)
  let note = Note::new(scope, tree, serials, save)
  let items : @component.KeyedChildren[String, Unit, ItemChild] = @component.KeyedChildren::new(
    scope, tree,
  )
  let buttons = [
    "Amber lamp", "Blue stool", "Refresh", "Toggle detail", "JPY", "USD",
  ].map(name => @semantics.add_button(tree, name).unwrap())
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
    buttons,
    wait,
    rate_result,
    task_control: None,
    size: (720, 500),
    error: None,
  }
  {
    title: "Item and quote board",
    editor: tree,
    default_input: Some(note.input),
    initial_size: model.size,
    viewport: None,
    publications: Some(publications),
    downstreams: Some(downstreams),
    serials: Some(serials),
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
      if reference == model.buttons[0] {
        model.request("amber", false)
      } else if reference == model.buttons[1] {
        model.request("blue", false)
      } else if reference == model.buttons[2] {
        model.request(model.selected.peek(), true)
      } else if reference == model.buttons[3] {
        if model.items.get(model.selected.peek()) is Some(item) {
          if item.details.get("detail") is Some(_) {
            ignore(item.details.clear())
          } else {
            ignore(item.show_detail(model))
          }
        }
        None
      } else if reference == model.buttons[4] {
        model.choose_currency("JPY")
      } else if reference == model.buttons[5] {
        model.choose_currency("USD")
      } else if reference == model.note.save_button {
        ignore(model.note.save())
        None
      } else {
        if model.items.get(model.selected.peek()) is Some(item) &&
          item.details.for_reference(reference) is Some(_) {
          model.quantity.set(model.quantity.peek() + 1)
        }
        None
      }
    },
    edited: edit => {
      if edit.target == model.note.input {
        model.note.edit(edit.text)
      }
      None
    },
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
pub fn create(wait : async (Int) -> Unit) -> @app.Application {
  create_with_rate(wait, _ => Ok(2))
}
