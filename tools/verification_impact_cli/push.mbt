///|
async fn resolve_push(input : String) -> Json {
  let updates = @impact.read_push_updates(input)
  let result : Array[Json] = []
  for update in updates {
    match update.local_oid {
      None => result.push({ "ref": update.remote_ref, "deleted": true })
      Some(oid) => {
        let resolved : Array[String] = []
        for kind in ["commit", "tree"] {
          let (code, output, _) = @process.collect_output(
            "git",
            ["rev-parse", "--verify", oid + "^{" + kind + "}"],
            no_console_window=true,
          )
          assert_eq(
            code,
            0,
            msg="push object must resolve to a local commit and tree",
          )
          let value = output.text().trim().to_owned()
          assert_false(
            value.is_empty() || value.contains("\n"),
            msg="unexpected Git revision output",
          )
          resolved.push(value)
        }
        result.push({
          "ref": update.remote_ref,
          "deleted": false,
          "commit": resolved[0],
          "tree": resolved[1],
        })
      }
    }
  }
  Json::array(result)
}
