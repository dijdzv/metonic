///|
pub fn backend() -> @editing.Backend {
  {
    read: @platform.read_text,
    write: text => {
      let normalized = text
        .replace_all(old="\r\n", new="\n")
        .replace_all(old="\r", new="\n")
      @platform.write_text(normalized.replace_all(old="\n", new="\r\n"))
    },
  }
}
