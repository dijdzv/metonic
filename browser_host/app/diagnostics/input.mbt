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
let shared_reader : Ref[((String) -> String?)?] = Ref(None)

///|
#export_name("sample")
pub fn sample() -> String {
  let fields : Array[Json] = []
  if shared_reader.val is Some(shared) {
    for field in ["text-input", "rpc-user"] {
      guard document().get_element_by_id(field) is Some(element) else {
        continue
      }
      let state = if field == "text-input" {
        @dom.HTMLTextAreaElement::from_js_value_opt(element.to_js_value()).map(input => {
          (
            input.get_value(),
            Some(input.get_selection_start()),
            Some(input.get_selection_end()),
          )
        })
      } else {
        @dom.HTMLInputElement::from_js_value_opt(element.to_js_value()).map(input => {
          (
            input.get_value(),
            input.get_selection_start(),
            input.get_selection_end(),
          )
        })
      }
      if state is Some((value, start, end)) {
        fields.push({
          "field": field.to_json(),
          "value": value.to_json(),
          "start": start.map(value => value.to_json()).unwrap_or(Json::null()),
          "end": end.map(value => value.to_json()).unwrap_or(Json::null()),
          "shared": shared(field)
          .map(value => value.to_json())
          .unwrap_or(Json::null()),
        })
      }
    }
  }
  // Event rows precede some browser default actions; they are not current state.
  (
    { "after_sequence": sequence.val.to_json(), "fields": fields.to_json() } :
    Json).stringify()
}

///|
fn record(
  field : String,
  event : String,
  value : String,
  start : Int?,
  end : Int?,
  shared : String?,
  detail : Json,
) -> Unit {
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
  shared_reader.val = None
}

///|
#export_name("snapshot")
pub fn snapshot() -> String {
  ({ "events": rows.to_json(), "total": sequence.val.to_json() } : Json).stringify()
}

///|
#export_name("start")
pub fn start(shared : (String) -> String?) -> Unit {
  stop()
  rows.clear()
  sequence.val = 0
  shared_reader.val = Some(shared)
  for field in ["text-input", "rpc-user"] {
    guard document().get_element_by_id(field) is Some(element) else { continue }
    let target = element.to_event_target()
    for
      name in [
        "beforeinput", "input", "compositionstart", "compositionupdate", "compositionend",
        "keydown", "keyup", "select", "focus", "blur",
      ] {
      let listener = @dom.EventListener::from_fn(event => {
        let detail : Json = if @dom.KeyboardEvent::from_js_value_opt(
            event.to_js_value(),
          )
          is Some(key) {
          {
            "key": key.get_key().to_json(),
            "composing": key.get_is_composing().to_json(),
          }
        } else if @dom.InputEvent::from_js_value_opt(event.to_js_value())
          is Some(input) {
          {
            "input_type": input.get_input_type().to_json(),
            "data": input.get_data().to_json(),
            "composing": input.get_is_composing().to_json(),
          }
        } else if @dom.CompositionEvent::from_js_value_opt(event.to_js_value())
          is Some(composition) {
          { "data": composition.get_data().to_json() }
        } else {
          { "kind": "other" }
        }
        if field == "text-input" {
          if @dom.HTMLTextAreaElement::from_js_value_opt(element.to_js_value())
            is Some(input) {
            record(
              field,
              name,
              input.get_value(),
              Some(input.get_selection_start()),
              Some(input.get_selection_end()),
              shared(field),
              detail,
            )
          }
        } else if @dom.HTMLInputElement::from_js_value_opt(
            element.to_js_value(),
          )
          is Some(input) {
          record(
            field,
            name,
            input.get_value(),
            input.get_selection_start(),
            input.get_selection_end(),
            shared(field),
            detail,
          )
        }
      })
      target.add_event_listener(name, Some(listener))
      listeners.push((target, name, listener))
    }
  }
}
