///|
struct Progress {
  line : Array[Byte]
  mut oversized : Bool
  mut completed : Int
}

///|
fn Progress::new() -> Progress {
  { line: [], oversized: false, completed: 0, }
}

///|
fn Progress::feed(self : Progress, bytes : Bytes) -> Array[String] {
  let messages = []
  for byte in bytes {
    if byte == b'\n' {
      if !self.oversized {
        let line = @utf8.decode_lossy(Bytes::from_array(self.line))
        let prefix = "HOOK_CHECK_OK: "
        if line.has_prefix(prefix) {
          self.completed += 1
          let label = line[prefix.length():].trim().to_owned()
          let label = if label.length() > 160 {
            label[:160].to_owned() + "..."
          } else {
            label
          }
          messages.push(
            "checks completed: " + self.completed.to_string() + " | " + label,
          )
        }
      }
      self.line.clear()
      self.oversized = false
    } else if self.line.length() < 8192 {
      self.line.push(byte)
    } else {
      self.oversized = true
    }
  }
  messages
}
