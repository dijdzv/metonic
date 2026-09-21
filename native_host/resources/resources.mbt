///|
pub suberror ResourceFailure {
  InvalidAssetPath(String)
  ExecutablePathUnavailable
} derive(Debug)

///|
#borrow(output)
extern "C" fn module_file_name(
  handle : UInt64,
  output : FixedArray[Byte],
  capacity : UInt,
) -> UInt = "GetModuleFileNameW"

///|
fn executable_directory() -> String raise ResourceFailure {
  executable_directory_with((output, capacity) => {
    module_file_name(0UL, output, capacity)
  })
}

///|
fn executable_directory_with(
  read : (FixedArray[Byte], UInt) -> UInt,
) -> String raise ResourceFailure {
  let mut capacity = 256
  while capacity <= 32768 {
    let output : FixedArray[Byte] = FixedArray::make(capacity * 2, 0)
    let length = read(output, capacity.reinterpret_as_uint()).reinterpret_as_int()
    if length == 0 {
      raise ExecutablePathUnavailable
    }
    if length < capacity {
      let path = @utf16.decode(
        Bytes::from_array(output[:length * 2]),
        endianness=Little,
        ignore_bom=true,
      ) catch {
        _ => raise ExecutablePathUnavailable
      }
      return parent_directory(path)
    }
    capacity *= 2
  }
  raise ExecutablePathUnavailable
}

///|
fn parent_directory(path : String) -> String raise ResourceFailure {
  let normalized = path.replace_all(old="\\", new="/")
  match normalized.rev_find("/") {
    Some(index) if index > 0 => normalized[:index].to_owned()
    _ => raise ExecutablePathUnavailable
  }
}

///|
pub fn asset_path(relative : String) -> String raise ResourceFailure {
  if !valid_relative_asset(relative) {
    raise InvalidAssetPath(relative)
  }
  executable_directory() + "/" + relative.replace_all(old="\\", new="/")
}

///|
fn valid_relative_asset(relative : String) -> Bool {
  !relative.contains(":") &&
  !relative.contains("\u0000") &&
  relative
  .replace_all(old="\\", new="/")
  .split("/")
  .all(part => part != "" && part != "." && part != "..")
}
