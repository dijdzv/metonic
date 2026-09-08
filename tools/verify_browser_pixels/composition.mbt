///|
fn highlighted_pixels(pixels : Bytes) -> Int {
  let mut count = 0
  for index = 0; index < pixels.length(); index = index + 4 {
    if pixels[index].to_int() == 180 && pixels[index + 2].to_int() == 255 {
      count += 1
    }
  }
  count
}

///|
async fn verify_composition_presentation(host : BrowserHost) -> Unit {
  for query in [false, true] {
    let selector = if query { "#rpc-user" } else { "#text-input" }
    let prefix = if query { "query-preedit-" } else { "editor-preedit-" }
    let original = command(host, { "op": "value", "selector": selector })
    ignore(command(host, { "op": "fill", "selector": selector, "value": "AB" }))
    ignore(
      command(host, {
        "op": "input-event",
        "selector": selector,
        "type": "select",
        "start": 1,
        "end": 1,
      }),
    )
    let initial = navigation_pixels(host, query, prefix + "initial")
    ignore(
      command(host, {
        "op": "input-event",
        "selector": selector,
        "type": "compositionstart",
      }),
    )
    ignore(
      command(host, {
        "op": "input-event",
        "selector": selector,
        "type": "compositionupdate",
        "data": "日本",
      }),
    )
    ignore(
      command(host, {
        "op": "input-event",
        "selector": selector,
        "type": "input",
        "composing": true,
        "value": "A日本B",
        "start": 3,
        "end": 3,
      }),
    )
    let end = navigation_pixels(host, query, prefix + "end")
    require(
      highlighted_pixels(end) > 100,
      "preedit range has no visible highlight " + selector,
    )
    ignore(
      command(host, {
        "op": "input-event",
        "selector": selector,
        "type": "input",
        "composing": true,
        "start": 2,
        "end": 2,
      }),
    )
    let moved = navigation_pixels(host, query, prefix + "moved")
    require(moved != end, "preedit cursor did not change pixels " + selector)
    require(
      highlighted_pixels(moved) > 100,
      "cursor movement lost preedit highlight " + selector,
    )
    ignore(
      command(host, {
        "op": "input-event",
        "selector": selector,
        "type": "input",
        "composing": true,
        "start": 3,
        "end": 3,
      }),
    )
    require(
      navigation_pixels(host, query, prefix + "returned") == end,
      "preedit cursor return changed text or highlight " + selector,
    )
    ignore(
      command(host, {
        "op": "input-event",
        "selector": selector,
        "type": "compositionend",
        "value": "AB",
        "start": 1,
        "end": 1,
      }),
    )
    require(
      navigation_pixels(host, query, prefix + "canceled") == initial,
      "composition cancellation did not restore pixels " + selector,
    )
    ignore(
      command(host, { "op": "fill", "selector": selector, "value": original }),
    )
  }
}
