///|
extern "js" fn document() -> @dom.Document =
  #| () => document

///|
let rows : Array[Json] = []

///|
let listeners : Array[(@dom.EventTarget, String, @dom.EventListener)] = []

///|
let sequence : Ref[Int] = Ref(0)

///|
fn record(field : String, event : String, value : String, start : Int?, end : Int?, shared : String, detail : Json) -> Unit {
  sequence.val += 1
  if rows.length() == 256 {
    ignore(rows.remove(0))
  }
  rows.push({
    "sequence": sequence.val.to_json(),
    "field": field.to_json(),
    "event": event.to_json(),
    "value": value.to_json(),
    "start": start.to_json(),
    "end": end.to_json(),
    "shared": shared.to_json(),
    "detail": detail,
  })
}

///|
#export_name("stop")
pub fn stop() -> Unit {
  for item in listeners {
    let (target, name, listener) = item
    target.remove_event_listener(name, Some(listener))
  }
  listeners.clear()
}

///|
#export_name("snapshot")
pub fn snapshot() -> String {
  ({ "events": rows.to_json(), "total": sequence.val.to_json() } : Json).stringify()
}

///|
#export_name("start")
pub fn start(shared : () -> String) -> Unit {
  stop()
  rows.clear()
  sequence.val = 0
  for field in ["text-input", "rpc-user"] {
    guard document().get_element_by_id(field) is Some(element) else { continue }
    let target = element.to_event_target()
    for name in ["beforeinput", "input", "compositionstart", "compositionupdate", "compositionend", "keydown", "keyup", "select", "focus", "blur"] {
      let listener = @dom.EventListener::from_fn(event => {
        let detail : Json = if @dom.KeyboardEvent::from_js_value_opt(event.to_js_value()) is Some(key) {
          { "key": key.get_key().to_json(), "composing": key.get_is_composing().to_json() }
        } else if @dom.InputEvent::from_js_value_opt(event.to_js_value()) is Some(input) {
          { "input_type": input.get_input_type().to_json(), "data": input.get_data().to_json(), "composing": input.get_is_composing().to_json() }
        } else if @dom.CompositionEvent::from_js_value_opt(event.to_js_value()) is Some(composition) {
          { "data": composition.get_data().to_json() }
        } else { { "kind": "other" } }
        if field == "text-input" {
          if @dom.HTMLTextAreaElement::from_js_value_opt(element.to_js_value()) is Some(input) {
            record(field, name, input.get_value(), Some(input.get_selection_start()), Some(input.get_selection_end()), shared(), detail)
          }
        } else if @dom.HTMLInputElement::from_js_value_opt(element.to_js_value()) is Some(input) {
          record(field, name, input.get_value(), input.get_selection_start(), input.get_selection_end(), shared(), detail)
        }
      })
      target.add_event_listener(name, Some(listener))
      listeners.push((target, name, listener))
    }
  }
}
