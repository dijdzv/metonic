///|
test "assets resolve relative to the executable, with Windows path separators" {
  assert_eq(
    parent_directory("C:\\apps\\日本語 📝\\notes.exe"),
    "C:/apps/日本語 📝",
  )
  assert_eq(parent_directory("C:/notes.exe"), "C:")
  assert_eq(parent_directory("\\\\server\\share\\notes.exe"), "//server/share")
  assert_true(valid_relative_asset("assets/NotoSansJP.ttf"))
  assert_true(valid_relative_asset("assets\\日本語.ttf"))
  for
    invalid in [
      "", "/font.ttf", "C:/font.ttf", "../font.ttf", "assets/../font.ttf", "assets//font.ttf",
      "assets/./font.ttf", "font.ttf:stream", "font\u0000.ttf",
    ] {
    assert_false(valid_relative_asset(invalid), msg=invalid)
  }
}

///|
test "executable paths retry truncation and preserve Unicode" {
  let directory = "C:/" + "directory/".repeat(40) + "日本語 📝"
  let path = directory + "/memo.exe"
  let bytes = @utf16.encode(path, bom=false, endianness=Little)
  let attempts : Array[UInt] = []
  let actual = executable_directory_with((output, capacity) => {
    attempts.push(capacity)
    if path.length() >= capacity.reinterpret_as_int() {
      return capacity
    }
    for index in 0..<bytes.length() {
      output[index] = bytes[index]
    }
    path.length().reinterpret_as_uint()
  })
  assert_eq(actual, directory)
  assert_eq(attempts, [256U, 512U])
}

///|
test "executable path failures and repeated truncation terminate" {
  let unavailable = try {
    ignore(executable_directory_with((_, _) => 0U))
    false
  } catch {
    ExecutablePathUnavailable => true
    _ => false
  }
  assert_true(unavailable)
  let attempts = Ref(0)
  let too_long = try {
    ignore(
      executable_directory_with((_, capacity) => {
        attempts.val += 1
        capacity
      }),
    )
    false
  } catch {
    ExecutablePathUnavailable => true
    _ => false
  }
  assert_true(too_long)
  assert_eq(attempts.val, 8)
}
