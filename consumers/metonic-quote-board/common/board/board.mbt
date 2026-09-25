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
priv struct Board {
  graph : @reactive.Graph
  scope : @reactive.Scope
  selected : @reactive.Signal[String]
  cycle : @reactive.Signal[@async_state.Cycle]
  quantity : @reactive.Signal[Int]
  detail : @async_state.Source[String, String]
  stock : @async_state.Source[String, Int]
  display : @async_state.Publication[(String, Int), Quote]
  tree : @semantics.Tree
  buttons : Array[@semantics.NodeRef]
  wait : async (Int) -> Unit
  mut size : (Int, Int)
  mut error : String?
}

///|
fn Board::request(
  self : Board,
  item : String,
  retain_previous : Bool,
) -> @task.Request? {
  let cycle = @async_state.Cycle::new()
  let detail_delay = if item == "amber" { 900 } else { 200 }
  let stock_delay = if item == "amber" { 200 } else { 900 }
  let detail = self.detail.replace(item, cycle, retain_previous, () => {
    (self.wait)(detail_delay)
    if item == "amber" {
      "Amber lamp"
    } else {
      "Blue stool"
    }
  })
  let stock = self.stock.replace(item, cycle, retain_previous, () => {
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
      self.selected.set(item)
      self.cycle.set(cycle)
    }),
  )
}

///|
fn Board::view(self : Board) -> Array[@app.Control] {
  let controls : Array[@app.Control] = []
  let names = ["Amber lamp", "Blue stool", "Quantity +", "Refresh"]
  for index, reference in self.buttons {
    let node = @semantics.node(self.tree, reference).unwrap()
    controls.push({
      element: {
        bounds: { x: 16 + index * 168, y: 16, width: 156, height: 36, },
        text: names[index],
        reference: Some(reference),
        focused: node.focused,
      },
      kind: @app.Button,
      clip: None,
    })
  }
  let item = self.selected.peek()
  let cycle = self.cycle.peek()
  let detail = match self.detail.current(item, cycle).view() {
    CurrentReady(name, _) => "Detail: " + name
    CurrentPending(_) => "Detail: loading"
    CurrentFailed(_) => "Detail: failed"
    _ => "Detail: waiting"
  }
  let stock = match self.stock.current(item, cycle).view() {
    CurrentReady(amount, _) => "Stock: " + amount.to_string()
    CurrentPending(_) => "Stock: loading"
    CurrentFailed(_) => "Stock: failed"
    _ => "Stock: waiting"
  }
  let quote = match self.display.get() {
    Some({ current: CurrentReady(value, _), .. }) =>
      "Shipping: " +
      value.shipping.to_string() +
      " for " +
      value.quantity.to_string()
    Some({ current: CurrentPending(_), previous: Some(previous), .. }) =>
      "Shipping: loading (previous " + previous.value.shipping.to_string() + ")"
    Some({ current: CurrentBlocked(_), previous: Some(previous), .. }) =>
      "Shipping: loading (previous " + previous.value.shipping.to_string() + ")"
    Some({ current: CurrentPending(_), .. }) => "Shipping: loading"
    Some({ current: CurrentFailed(_), .. }) => "Shipping: failed"
    _ => "Shipping: waiting for item"
  }
  let lines = [
    "Item: " + item + " · Quantity: " + self.quantity.peek().to_string(),
    detail,
    stock,
    quote,
  ]
  for index, line in lines {
    controls.push({
      element: {
        bounds: {
          x: 16,
          y: 72 + index * 48,
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
  if self.error is Some(message) {
    controls.push({
      element: {
        bounds: {
          x: 16,
          y: 272,
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
pub fn create(wait : async (Int) -> Unit) -> @app.Application {
  let graph = @reactive.Graph::new()
  let scope = @reactive.Scope::root(graph)
  let selected = @reactive.Signal::new(scope, "amber")
  let cycle = @reactive.Signal::new(scope, @async_state.Cycle::new())
  let quantity = @reactive.Signal::new(scope, 1)
  let detail : @async_state.Source[String, String] = @async_state.Source::new(
    scope,
  )
  let stock : @async_state.Source[String, Int] = @async_state.Source::new(scope)
  let downstreams = @async_state.DownstreamRegistry::new(scope)
  let quote = downstreams.register(
    scope,
    () => {
      let related = @async_state.Related::new(selected.get(), cycle.get())
      @async_state.join_related(related.read(detail), related.read(stock), fn(
        name,
        amount,
      ) {
        ItemPair::{ name, stock: amount, }
      })
      .current()
      .map(pair => QuoteInput::{
        name: pair.name,
        stock: pair.stock,
        quantity: quantity.get(),
      })
    },
    input => {
      wait(250)
      {
        name: input.name,
        stock: input.stock,
        quantity: input.quantity,
        shipping: (100 + input.stock) * input.quantity,
      }
    },
  )
  let publications = @async_state.PublicationRegistry::new(scope)
  let display = publications.register(scope, () => {
    ((selected.get(), quantity.get()), quote.current())
  })
  let tree = @semantics.empty(1, 1)
  let buttons = ["Amber lamp", "Blue stool", "Quantity +", "Refresh"].map(name => {
    @semantics.add_button(tree, name).unwrap()
  })
  let model : Board = {
    graph,
    scope,
    selected,
    cycle,
    quantity,
    detail,
    stock,
    display,
    tree,
    buttons,
    wait,
    size: (720, 320),
    error: None,
  }
  {
    title: "Item and quote board",
    editor: tree,
    default_input: None,
    initial_size: model.size,
    viewport: None,
    publications: Some(publications),
    downstreams: Some(downstreams),
    connect_tasks: control => {
      if !model.detail.connect(control) ||
        !model.stock.connect(control) ||
        !downstreams.connect(control) {
        abort("quote board task connection failed")
      }
    },
    initialize: () => model.request("amber", false),
    view: () => model.view(),
    activate: reference => {
      if reference == model.buttons[0] {
        model.request("amber", false)
      } else if reference == model.buttons[1] {
        model.request("blue", false)
      } else if reference == model.buttons[2] {
        model.quantity.set(model.quantity.peek() + 1)
        None
      } else if reference == model.buttons[3] {
        model.request(model.selected.peek(), true)
      } else {
        None
      }
    },
    edited: _ => None,
    resize: (width, height) => {
      if width < 700 || height < 300 {
        return false
      }
      let changed = model.size != (width, height)
      model.size = (width, height)
      changed
    },
    stop: () => (),
    can_close: () => true,
    close_requested: () => (),
    close_ready: () => false,
    input_error: message => model.error = message,
    dispose: () => model.scope.dispose(),
  }
}
