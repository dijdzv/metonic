///|
test "pre-push input preserves new branches updates and deletions independently" {
  let zero = "0000000000000000000000000000000000000000"
  let first = "1111111111111111111111111111111111111111"
  let second = "2222222222222222222222222222222222222222"
  let input = "HEAD " +
    first +
    " refs/heads/new " +
    zero +
    "\n" +
    "refs/heads/topic " +
    second +
    " refs/heads/topic " +
    first +
    "\r\n" +
    "(delete) " +
    zero +
    " refs/heads/old " +
    second +
    "\n"
  assert_eq(read_push_updates(input), [
    {
      local_ref: "HEAD",
      local_oid: Some(first),
      remote_ref: "refs/heads/new",
      remote_oid: None,
    },
    {
      local_ref: "refs/heads/topic",
      local_oid: Some(second),
      remote_ref: "refs/heads/topic",
      remote_oid: Some(first),
    },
    {
      local_ref: "(delete)",
      local_oid: None,
      remote_ref: "refs/heads/old",
      remote_oid: Some(second),
    },
  ])
  assert_eq(read_push_updates(""), [])
  for
    invalid in [
      input + input,
      "HEAD abc refs/heads/main " + zero,
      "HEAD " + zero + " refs/heads/main " + zero,
    ] {
    let rejected = try {
      ignore(read_push_updates(invalid))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
