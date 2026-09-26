///|
test "work-order snapshot round-trips Unicode and closed state" {
  let orders = [
    WorkOrder::{
      id: "WO-1",
      title: "点検😀",
      details: "配線を確認",
      closed: true,
    },
  ]
  assert_eq(decode_orders(encode_orders(orders)), Ok(orders))
}

///|
test "missing and malformed work-order snapshots are not interchangeable" {
  assert_eq(decode_orders(""), Err("Unrecognized work-order snapshot"))
  assert_eq(
    decode_orders("METONIC_WORK_ORDERS\n{"),
    Err("Malformed work-order snapshot"),
  )
  assert_eq(
    decode_orders("METONIC_WORK_ORDERS\n{\"version\":2,\"orders\":[]}"),
    Err("Unsupported work-order snapshot version"),
  )
}

///|
test "work-order snapshot rejects duplicate identities" {
  let orders = [
    WorkOrder::{ id: "WO-1", title: "First", details: "", closed: false, },
    WorkOrder::{ id: "WO-1", title: "Second", details: "", closed: false, },
  ]
  assert_eq(
    decode_orders(encode_orders(orders)),
    Err("Invalid or duplicate work-order ID"),
  )
}
