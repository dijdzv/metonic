///|
pub(all) struct Note {
  id : Int
  text : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) enum MoveDirection {
  Up
  Down
} derive(Eq, Debug)

///|
pub struct Document {
  priv version : Int
  priv next_id : Int
  priv notes : Array[Note]
} derive(Eq, Debug, ToJson, FromJson)

///|
pub fn empty() -> Document {
  { version: 1, next_id: 1, notes: [], }
}

///|
pub fn Document::items(self : Document) -> Array[Note] {
  self.notes.copy()
}

///|
pub fn Document::find(self : Document, id : Int) -> Note? {
  self.notes.iter().find_first(note => note.id == id)
}

///|
pub fn Document::create_note(
  self : Document,
) -> Result[(Document, Int), String] {
  guard self.next_id < 2147483647 else { return Err("Memo ID limit reached") }
  let id = self.next_id
  let notes = self.notes.copy()
  notes.push({ id, text: "", })
  Ok(({ version: 1, next_id: id + 1, notes, }, id))
}

///|
pub fn Document::edit(
  self : Document,
  id : Int,
  text : String,
) -> Result[Document, String] {
  guard text.length() <= 1024 else {
    return Err("Memo exceeds the editor text limit")
  }
  guard self.find(id) is Some(_) else { return Err("Memo no longer exists") }
  Ok({
    ..self,
    notes: self.notes.map(note => {
      if note.id == id {
        { id, text, }
      } else {
        note
      }
    }),
  })
}

///|
pub fn Document::remove(self : Document, id : Int) -> Result[Document, String] {
  guard self.find(id) is Some(_) else { return Err("Memo no longer exists") }
  Ok({ ..self, notes: self.notes.filter(note => note.id != id), })
}

///|
pub fn Document::reorder(
  self : Document,
  id : Int,
  direction : MoveDirection,
) -> Result[Document, String] {
  let mut position = -1
  for index, note in self.notes {
    if note.id == id {
      position = index
      break
    }
  }
  guard position >= 0 else { return Err("Memo no longer exists") }
  let destination = match direction {
    Up => position - 1
    Down => position + 1
  }
  if destination < 0 || destination >= self.notes.length() {
    return Ok({ ..self, notes: self.notes.copy(), })
  }
  let notes = self.notes.copy()
  let adjacent = notes[destination]
  notes[destination] = notes[position]
  notes[position] = adjacent
  Ok({ ..self, notes, })
}

///|
pub fn Document::encode(self : Document) -> String {
  "METONIC_NOTES\n" + ToJson::to_json(self).stringify()
}

///|
pub fn decode(snapshot : String?) -> Result[Document, String] {
  guard snapshot is Some(text) else { return Ok(empty()) }
  guard text.strip_prefix("METONIC_NOTES\n") is Some(payload) else {
    guard text.length() <= 1024 else {
      return Err("Stored memo exceeds the editor text limit")
    }
    return Ok({ version: 1, next_id: 2, notes: [{ id: 1, text, }], })
  }
  let document : Document = @json.from_json(@json.parse(payload.to_owned())) catch {
    _ => return Err("Stored memo collection is malformed")
  }
  guard document.version == 1 else {
    return Err("Unsupported memo collection version")
  }
  guard document.next_id > 0 else { return Err("Invalid next memo ID") }
  let seen : Set[Int] = Set([])
  for note in document.notes {
    guard note.id > 0 && note.id < document.next_id && !seen.contains(note.id) else {
      return Err("Invalid or duplicate memo ID")
    }
    guard note.text.length() <= 1024 else {
      return Err("Stored memo exceeds the editor text limit")
    }
    seen.add(note.id)
  }
  Ok(document)
}
