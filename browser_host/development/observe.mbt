///|
#export_name("query_state_json")
pub fn query_state_json() -> String {
  let (text, start, end, composing) = @app.query_state()
  (
    {
      "text": text.to_json(),
      "start": start.to_json(),
      "end": end.to_json(),
      "composing": composing.to_json(),
    } : Json).stringify()
}
