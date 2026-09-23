///|
pub struct Model {
  priv operation : @task.Operation
  priv wait : async (Int) -> Unit
  priv mut document : @collection.Document
  priv query : @reactive.Signal[String]
  priv mut generation : Int
  priv mut closed : Bool
  priv matching : @reactive.Signal[Array[@collection.Note]]
}

///|
pub fn create(
  scope : @reactive.Scope,
  wait : async (Int) -> Unit,
) -> Model {
  let model : Model = {
    operation: @task.Operation::new(),
    wait,
    document: @collection.empty(),
    query: @reactive.Signal::new(scope, ""),
    generation: 0,
    closed: false,
    matching: @reactive.Signal::new(scope, []),
  }
  scope.on_dispose(() => {
    model.closed = true
    model.generation += 1
  })
  model
}

///|
fn matching(document : @collection.Document, query : String) -> Array[@collection.Note] {
  let query = query.to_lower()
  document
  .items()
  .filter(note => query == "" || note.text.to_lower().contains(query))
}

///|
pub fn Model::refresh(self : Model, document : @collection.Document) -> Unit {
  if !self.closed && self.document != document {
    self.document = document
    self.generation += 1
    self.matching.set(matching(document, self.query.peek()))
  }
}

///|
pub fn Model::items(self : Model) -> Array[@collection.Note] {
  self.matching.get().copy()
}

///|
pub fn Model::filtered(self : Model) -> Bool {
  self.query.get() != ""
}

///|
pub fn Model::cancel_running(self : Model, control : @task.TaskControl) -> Unit {
  control.cancel(self.operation)
}

///|
pub fn Model::request(
  self : Model,
  query : String,
  changed : () -> Unit,
) -> @task.Request? {
  guard !self.closed else { return None }
  self.generation += 1
  let generation = self.generation
  self.query.set(query)
  let document = self.document
  if query == "" {
    self.matching.set(matching(document, query))
    changed()
    return Some(@task.cancel(() => (), operation=self.operation))
  }
  Some(
    @task.replace(
      () => (),
      () => {
        Some(
          @task.work(
            () => {
              (self.wait)(100)
              matching(document, query)
            },
            ids => {
              if self.closed ||
                self.generation != generation ||
                self.document != document {
                return @task.Rejected
              }
              self.matching.set(ids)
              changed()
              @task.Changed
            },
          ),
        )
      },
      operation=self.operation,
    ),
  )
}

///|
pub fn Model::close(self : Model) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.generation += 1
  self.matching.set([])
}
