///|
pub struct Model {
  priv resource : @resource.Resource
  priv wait : async (Int) -> Unit
  priv mut document : @collection.Document
  priv query : @reactive.Signal[String]
  // Resource generations advance on admission; query/document edits must invalidate even without admission.
  priv mut generation : Int
  priv mut closed : Bool
  priv matching : @reactive.Signal[Array[@collection.Note]]
}

///|
pub fn create(scope : @reactive.Scope, wait : async (Int) -> Unit) -> Model {
  let model : Model = {
    resource: @resource.Resource::new(scope),
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
fn matching(
  document : @collection.Document,
  query : String,
) -> Array[@collection.Note] {
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
pub fn Model::connect_tasks(self : Model, control : @task.TaskControl) -> Bool {
  self.resource.connect(control)
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
    return self.resource.cancel(() => ())
  }
  self.resource.replace(
    () => (),
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
  self.resource.dispose()
}
