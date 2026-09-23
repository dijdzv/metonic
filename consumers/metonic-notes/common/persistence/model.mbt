///|
pub(all) enum State {
  Unloaded
  Loading
  Ready
  Saving
  LoadFailed(String)
  SaveFailed(String)
  Closed
} derive(Eq, Debug)

///|
pub struct Model {
  priv state_value : @reactive.Signal[State]
  priv batch : ((() -> Unit) -> Unit)
  priv mut text_value : String
  priv mut saved : String?
  priv mut generation : Int
  priv mut pending : String?
  priv mut receipt : Result[Unit, String]?
  priv mut closed : Bool
}

///|
pub fn create() -> Model {
  create_scoped(@reactive.Scope::root(@reactive.Graph::new()), action => action())
}

///|
pub fn create_scoped(
  scope : @reactive.Scope,
  batch : ((() -> Unit) -> Unit),
) -> Model {
  let model : Model = {
    state_value: @reactive.Signal::new(scope, Unloaded),
    batch,
    text_value: "",
    saved: None,
    generation: 0,
    pending: None,
    receipt: None,
    closed: false,
  }
  scope.on_dispose(() => model.closed = true)
  model
}

///|
pub fn Model::state(self : Model) -> State {
  if self.closed {
    return Closed
  }
  self.state_value.get()
}

///|
pub fn Model::text(self : Model) -> String {
  self.text_value
}

///|
pub fn Model::is_saved(self : Model, text : String) -> Bool {
  self.saved == Some(text)
}

///|
pub fn Model::dirty(self : Model) -> Bool {
  self.saved is Some(value) && value != self.text_value
}

///|
pub fn Model::edit(self : Model, text : String) -> Bool {
  if self.closed {
    return false
  }
  match self.state_value.peek() {
    Ready | Saving | SaveFailed(_) => {
      self.text_value = text
      true
    }
    _ => false
  }
}

///|
pub fn Model::begin_load(self : Model) -> Int? {
  if self.closed {
    return None
  }
  match self.state_value.peek() {
    Unloaded | LoadFailed(_) => {
      self.generation += 1
      self.state_value.set(Loading)
      Some(self.generation)
    }
    _ => None
  }
}

///|
pub fn Model::finish_load(
  self : Model,
  ticket : Int,
  result : Result[String?, String],
) -> Bool {
  if self.closed {
    return false
  }
  guard self.state_value.peek() == Loading && self.generation == ticket else {
    return false
  }
  match result {
    Ok(value) => {
      self.text_value = value.unwrap_or("")
      self.saved = Some(self.text_value)
      self.state_value.set(Ready)
    }
    Err(message) => self.state_value.set(LoadFailed(message))
  }
  true
}

///|
pub fn Model::begin_save(self : Model) -> (Int, String)? {
  if self.closed {
    return None
  }
  match self.state_value.peek() {
    Ready | SaveFailed(_) => {
      self.generation += 1
      self.pending = Some(self.text_value)
      self.receipt = None
      self.state_value.set(Saving)
      Some((self.generation, self.text_value))
    }
    _ => None
  }
}

///|
pub fn Model::finish_save(
  self : Model,
  ticket : Int,
  result : Result[Unit, String],
) -> Bool {
  if self.closed {
    return false
  }
  guard self.state_value.peek() == Saving && self.generation == ticket else {
    return false
  }
  match result {
    Ok(_) => {
      self.saved = self.pending
      self.state_value.set(Ready)
    }
    Err(message) => self.state_value.set(SaveFailed(message))
  }
  self.pending = None
  self.receipt = None
  true
}

///|
fn Model::record_save(
  self : Model,
  ticket : Int,
  result : Result[Unit, String],
) -> Unit {
  if self.closed {
    return
  }
  if self.state_value.peek() == Saving && self.generation == ticket {
    self.receipt = Some(result)
  }
}

///|
pub fn Model::retire_save(self : Model) -> Unit {
  if self.closed {
    return
  }
  if self.state_value.peek() == Saving {
    match self.receipt {
      Some(result) => ignore(self.finish_save(self.generation, result))
      None => ignore(self.cancel_save(self.generation))
    }
  }
}

///|
pub fn Model::saved_text(self : Model) -> String? {
  self.saved
}

///|
pub fn Model::can_close(self : Model) -> Bool {
  if self.closed {
    return false
  }
  self.state_value.peek() != Saving && !self.dirty()
}

///|
pub fn Model::cancel_save(self : Model, ticket : Int) -> Bool {
  if self.closed {
    return false
  }
  guard self.state_value.peek() == Saving && self.generation == ticket else {
    return false
  }
  self.generation += 1
  self.pending = None
  self.receipt = None
  self.state_value.set(Ready)
  true
}

///|
pub fn Model::discard(self : Model) -> String? {
  if self.closed {
    return None
  }
  match self.state_value.peek() {
    Ready | SaveFailed(_) => {
      guard self.saved is Some(text) else { return None }
      self.text_value = text
      self.state_value.set(Ready)
      Some(text)
    }
    _ => None
  }
}

///|
pub fn Model::close(self : Model) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.generation += 1
  self.pending = None
  self.receipt = None
  self.state_value.set(Closed)
}
