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
  priv mut state_value : State
  priv mut text_value : String
  priv mut saved : String?
  priv mut generation : Int
  priv mut pending : String?
  priv mut receipt : Result[Unit, String]?
}

///|
pub fn create() -> Model {
  {
    state_value: Unloaded,
    text_value: "",
    saved: None,
    generation: 0,
    pending: None,
    receipt: None,
  }
}

///|
pub fn Model::state(self : Model) -> State {
  self.state_value
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
  match self.state_value {
    Ready | Saving | SaveFailed(_) => {
      self.text_value = text
      true
    }
    _ => false
  }
}

///|
pub fn Model::begin_load(self : Model) -> Int? {
  match self.state_value {
    Unloaded | LoadFailed(_) => {
      self.generation += 1
      self.state_value = Loading
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
  guard self.state_value == Loading && self.generation == ticket else {
    return false
  }
  match result {
    Ok(value) => {
      self.text_value = value.unwrap_or("")
      self.saved = Some(self.text_value)
      self.state_value = Ready
    }
    Err(message) => self.state_value = LoadFailed(message)
  }
  true
}

///|
pub fn Model::begin_save(self : Model) -> (Int, String)? {
  match self.state_value {
    Ready | SaveFailed(_) => {
      self.generation += 1
      self.pending = Some(self.text_value)
      self.receipt = None
      self.state_value = Saving
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
  guard self.state_value == Saving && self.generation == ticket else {
    return false
  }
  match result {
    Ok(_) => {
      self.saved = self.pending
      self.state_value = Ready
    }
    Err(message) => self.state_value = SaveFailed(message)
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
  if self.state_value == Saving && self.generation == ticket {
    self.receipt = Some(result)
  }
}

///|
pub fn Model::retire_save(self : Model) -> Unit {
  if self.state_value == Saving {
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
  self.state_value != Saving && !self.dirty()
}

///|
pub fn Model::cancel_save(self : Model, ticket : Int) -> Bool {
  guard self.state_value == Saving && self.generation == ticket else {
    return false
  }
  self.generation += 1
  self.pending = None
  self.receipt = None
  self.state_value = Ready
  true
}

///|
pub fn Model::discard(self : Model) -> String? {
  match self.state_value {
    Ready | SaveFailed(_) => {
      guard self.saved is Some(text) else { return None }
      self.text_value = text
      self.state_value = Ready
      Some(text)
    }
    _ => None
  }
}

///|
pub fn Model::close(self : Model) -> Unit {
  self.generation += 1
  self.pending = None
  self.receipt = None
  self.state_value = Closed
}
