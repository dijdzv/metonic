///|
test "multiple Japanese memos survive serialization and independent edits" {
  let (first, a) = empty().create_note().unwrap()
  let first = first.edit(a, "日本語\n一つ目").unwrap()
  let (second, b) = first.create_note().unwrap()
  let second = second.edit(b, "二つ目").unwrap()
  assert_eq(first.items().length(), 1)
  assert_eq(first.find(a).unwrap().text, "日本語\n一つ目")
  assert_eq(decode(Some(second.encode())), Ok(second))
  let removed = second.remove(a).unwrap()
  assert_eq(removed.find(b).unwrap().text, "二つ目")
  let (third, c) = removed.create_note().unwrap()
  assert_true(c > b)
  assert_eq(third.items().length(), 2)
  assert_eq(second.items().length(), 2)
}

///|
test "missing storage and a legacy empty memo are distinct" {
  assert_eq(decode(None).unwrap().items().length(), 0)
  assert_eq(decode(Some("")).unwrap().items(), [{ id: 1, text: "", }])
  let legacy = decode(Some("保存済み\nメモ")).unwrap()
  assert_eq(legacy.items(), [{ id: 1, text: "保存済み\nメモ", }])
  assert_eq(decode(Some(legacy.encode())), Ok(legacy))
}

///|
test "invalid collection data is an error rather than an empty replacement" {
  for
    payload in [
      "broken", "{\"version\":2,\"next_id\":1,\"notes\":[]}", "{\"version\":1,\"next_id\":0,\"notes\":[]}",
      "{\"version\":1,\"next_id\":2,\"notes\":[{\"id\":1,\"text\":\"a\"},{\"id\":1,\"text\":\"b\"}]}",
      "{\"version\":1,\"next_id\":1,\"notes\":[{\"id\":1,\"text\":\"a\"}]}",
    ] {
    assert_true(decode(Some("METONIC_NOTES\n" + payload)) is Err(_))
  }
}

///|
test "deleting the last note preserves the ID sequence and unknown edits fail" {
  let (document, id) = empty().create_note().unwrap()
  let deleted = document.remove(id).unwrap()
  assert_eq(deleted.items(), [])
  assert_true(deleted.edit(id, "lost") is Err(_))
  assert_true(deleted.remove(id) is Err(_))
  let (_, next) = decode(Some(deleted.encode())).unwrap().create_note().unwrap()
  assert_true(next > id)
}

///|
test "moving swaps adjacent memos without changing the source snapshot or IDs" {
  let (one, first) = empty().create_note().unwrap()
  let one = one.edit(first, "first").unwrap()
  let (two, second) = one.create_note().unwrap()
  let two = two.edit(second, "second").unwrap()
  let (three, third) = two.create_note().unwrap()
  let document = three.edit(third, "third").unwrap()
  let source_items = document.items()
  let source_snapshot = document.encode()

  let moved = document.reorder(third, MoveDirection::Up).unwrap()
  assert_eq(moved.items(), [
    { id: first, text: "first", },
    { id: third, text: "third", },
    { id: second, text: "second", },
  ])
  assert_eq(document.items(), source_items)
  assert_eq(document.encode(), source_snapshot)
  let moved_back = moved.reorder(third, MoveDirection::Down).unwrap()
  assert_eq(moved_back.items(), source_items)

  let decoded = decode(Some(moved.encode())).unwrap()
  assert_eq(decoded, moved)
  assert_eq(decoded.items(), moved.items())
  let (_, next_id) = decoded.create_note().unwrap()
  assert_eq(next_id, third + 1)
}

///|
test "moving at either boundary is a no-op and unknown IDs fail" {
  let (one, first) = empty().create_note().unwrap()
  let (two, second) = one.create_note().unwrap()
  let source_snapshot = two.encode()
  assert_eq(two.reorder(first, MoveDirection::Up), Ok(two))
  assert_eq(two.reorder(second, MoveDirection::Down), Ok(two))
  assert_eq(two.reorder(999, MoveDirection::Up), Err("Memo no longer exists"))
  assert_eq(two.encode(), source_snapshot)
}
