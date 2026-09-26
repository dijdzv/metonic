///|
struct StoredDocument {
  version : Int
  orders : Array[WorkOrder]
} derive(ToJson, FromJson)

///|
fn encode_orders(orders : Array[WorkOrder]) -> String {
  "METONIC_WORK_ORDERS\n" +
  ToJson::to_json(StoredDocument::{ version: 1, orders, }).stringify()
}

///|
fn decode_orders(text : String) -> Result[Array[WorkOrder], String] {
  guard text.strip_prefix("METONIC_WORK_ORDERS\n") is Some(payload) else {
    return Err("Unrecognized work-order snapshot")
  }
  let document : StoredDocument = @json.from_json(
    @json.parse(payload.to_owned()),
  ) catch {
    _ => return Err("Malformed work-order snapshot")
  }
  guard document.version == 1 else {
    return Err("Unsupported work-order snapshot version")
  }
  let ids : Set[String] = Set([])
  for order in document.orders {
    guard order.id != "" && !ids.contains(order.id) else {
      return Err("Invalid or duplicate work-order ID")
    }
    guard order.id.length() <= 1024 &&
      order.title.length() <= 1024 &&
      order.details.length() <= 1024 else {
      return Err("Work-order field exceeds the editor limit")
    }
    ids.add(order.id)
  }
  Ok(document.orders)
}
