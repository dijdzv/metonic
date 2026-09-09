///|
async fn matching_record(config : String, record : String) -> Bool {
  if !@fs.exists(record) {
    return false
  }
  let lock = record + ".lock"
  @fs.mkdir(lock)
  defer @async.protect_from_cancel(() => @fs.rmdir(lock, recursive=true))
  let contents = @fs.read_file(record).text()
  let parsed : Map[String, Json] = @json.from_json(@json.parse(contents)) catch {
    _ => return false
  }
  if parsed.get("success") != Some(Json::boolean(true)) {
    return false
  }
  guard parsed.get("fingerprint") is Some(saved) else { return false }
  saved == fingerprint(config)
}

///|
async fn record_verification(
  config : String,
  record : String,
  verify : async () -> Unit,
) -> Unit {
  let lock = record + ".lock"
  @fs.mkdir(lock)
  defer @async.protect_from_cancel(() => @fs.rmdir(lock, recursive=true))
  @fs.write_file(record, "{\"success\":false}")
  let before = fingerprint(config)
  verify()
  let after = fingerprint(config)
  assert_eq(before, after, msg="verification inputs changed during execution")
  let result : Json = { "success": true, "fingerprint": after }
  let temporary = lock + "/success.json"
  @fs.write_file(temporary, result.stringify())
  @fs.rename(temporary, record, replace=true)
}
