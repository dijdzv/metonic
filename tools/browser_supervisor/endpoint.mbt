///|
fn ready_endpoint(line : String) -> String raise Error {
  let prefix = "http://127.0.0.1:"
  guard line.has_prefix(prefix) && line.has_suffix("/\n") else {
    fail("invalid browser server readiness")
    return ""
  }
  let digits = line[prefix.length():line.length() - 2]
  guard digits.length() > 0 && digits.length() <= 5 else {
    fail("invalid browser server readiness")
    return ""
  }
  let mut port = 0
  for digit in digits.iter() {
    guard digit >= '0' && digit <= '9' else {
      fail("invalid browser server readiness")
      return ""
    }
    port = port * 10 + digit.to_int() - '0'.to_int()
  }
  guard port > 0 && port <= 65535 else {
    fail("invalid browser server readiness")
    return ""
  }
  prefix + port.to_string()
}
