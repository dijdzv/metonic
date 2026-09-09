///|
pub struct PushUpdate {
  local_ref : String
  local_oid : String?
  remote_ref : String
  remote_oid : String?
} derive(Debug, Eq)

///|
fn push_oid(value : String) -> String? raise {
  assert_true(
    value.length() == 40 || value.length() == 64,
    msg="unsupported Git object ID length",
  )
  assert_true(
    value.iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')),
    msg="invalid Git object ID",
  )
  if value.iter().all(c => c == '0') {
    None
  } else {
    Some(value)
  }
}

///|
pub fn read_push_updates(input : String) -> Array[PushUpdate] raise {
  let updates : Array[PushUpdate] = []
  let refs : Map[String, Bool] = Map([])
  for raw in input.split("\n") {
    let line = raw.trim().to_owned()
    if line.is_empty() {
      continue
    }
    let fields = line
      .replace_all(old="\t", new=" ")
      .split(" ")
      .filter(part => !part.is_empty())
      .map(part => part.to_owned())
      .collect()
    assert_eq(fields.length(), 4, msg="expected four pre-push fields")
    assert_eq(
      fields[1].length(),
      fields[3].length(),
      msg="mixed Git object formats",
    )
    let local_oid = push_oid(fields[1])
    let remote_oid = push_oid(fields[3])
    assert_false(
      local_oid is None && remote_oid is None,
      msg="push has no source or destination object",
    )
    assert_true(
      fields[2].has_prefix("refs/") && fields[2].length() > 5,
      msg="missing remote ref",
    )
    assert_false(refs.contains(fields[2]), msg="duplicate remote ref")
    refs[fields[2]] = true
    updates.push({
      local_ref: fields[0],
      local_oid,
      remote_ref: fields[2],
      remote_oid,
    })
  }
  updates
}
