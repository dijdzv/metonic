///|
async test "deletion-only discovery dispatch does not read missing record or launch commands" {
  let zero = "0000000000000000000000000000000000000000"
  run_discovered_push(
    "missing-checkout",
    "(delete) " +
    zero +
    " refs/heads/deleted 1111111111111111111111111111111111111111",
    "missing-record",
    ["missing-discovery"],
    ["missing-commit"],
    ["missing-full"],
    ["missing-remainder"],
  )
}

///|
async test "discovery failure invalidates prior success before any command runs" {
  let directory = @fs.tmpdir(prefix="metonic-discovery-failure")
  let record = directory + "/success.json"
  @fs.write_file(record, "{\"success\":true}")
  let failed = try {
    record_discovered_index(
      directory,
      record,
      ["metonic-missing-discovery-command"],
      ["metonic-verification-must-not-run"],
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  let result : Map[String, Json] = @json.from_json(
    @json.parse(@fs.read_file(record).text()),
  )
  assert_eq(result.get("success"), Some(Json::boolean(false)))
  assert_false(@fs.exists(record + ".lock"))
}
