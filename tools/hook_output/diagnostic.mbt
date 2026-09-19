///|
fn failure_output(text : String, truncated~ : Bool) -> String {
  let lines = text.split("\n").map(line => line.to_owned()).to_array()
  let mut failure = -1
  for index in 0..<lines.length() {
    if lines[index].has_prefix("command failed (") {
      failure = index
    }
  }
  let mut start = 0
  let mut end = lines.length()
  let mut heading = "Verification diagnostic:"
  if failure >= 0 {
    end = failure
    for index in 0..<failure {
      if lines[index].has_prefix("pre-commit: ") {
        heading = "Failed check: " + lines[index][12:].to_owned()
        start = index + 1
      }
      if lines[index].has_prefix("pre-commit timing: ") {
        end = index
      }
    }
  } else {
    for index in 0..<lines.length() {
      if lines[index].has_prefix("Failure(") ||
        lines[index].has_prefix("Error:") ||
        lines[index].has_prefix("error:") ||
        lines[index].has_prefix("fatal:") {
        start = index
        break
      }
    }
  }
  let mut shortened = truncated
  if end - start > 80 {
    start = end - 80
    shortened = true
  }
  let mut body = lines[start:end].join("\n").trim().to_owned()
  if body.length() > 12000 {
    body = body[body.length() - 12000:].to_owned()
    shortened = true
  }
  if body.is_empty() {
    body = "The command failed without diagnostic output."
  }
  heading +
  "\n" +
  body +
  (if shortened {
    "\n[Diagnostic truncated; see the full log above.]"
  } else {
    ""
  })
}
