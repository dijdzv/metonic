///|
pub struct Model {
  priv operation : @task.Operation
  priv wait : async (Int) -> Unit
  priv mut document : @collection.Document
  priv mut query : String
  priv mut generation : Int
  priv mut closed : Bool
  priv mut matching : Array[@collection.Note]
}

///|
pub fn create(wait : async (Int) -> Unit) -> Model {
  {
    operation: @task.Operation::new(),
    wait,
    document: @collection.empty(),
    query: "",
    generation: 0,
    closed: false,
    matching: [],
  }
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
    self.matching = matching(document, self.query)
  }
}

///|
pub fn Model::items(self : Model) -> Array[@collection.Note] {
  self.matching.copy()
}

///|
pub fn Model::filtered(self : Model) -> Bool {
  self.query != ""
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
  self.query = query
  let document = self.document
  if query == "" {
    self.matching = matching(document, query)
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
              self.matching = ids
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
  self.closed = true
  self.generation += 1
  self.matching.clear()
}
