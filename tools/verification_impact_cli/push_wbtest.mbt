///|
async test "push resolution uses requested objects and rejects missing objects" {
  let (code, output, _) = @process.collect_output(
    "git",
    ["rev-parse", "HEAD", "HEAD^{tree}"],
    no_console_window=true,
  )
  assert_eq(code, 0)
  let objects = output
    .text()
    .trim()
    .split("\n")
    .map(line => line.trim().to_owned())
    .collect()
  assert_eq(objects.length(), 2)
  let zero = "0000000000000000000000000000000000000000"
  let input = "HEAD " +
    objects[0] +
    " refs/heads/new " +
    zero +
    "\n(delete) " +
    zero +
    " refs/heads/old " +
    objects[0]
  let expected : Json = [
    {
      "ref": "refs/heads/new",
      "deleted": false,
      "commit": objects[0],
      "tree": objects[1],
    },
    { "ref": "refs/heads/old", "deleted": true },
  ]
  assert_eq(resolve_push(input), expected)
  let rejected = try {
    ignore(
      resolve_push(
        "HEAD 1111111111111111111111111111111111111111 refs/heads/new " + zero,
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
