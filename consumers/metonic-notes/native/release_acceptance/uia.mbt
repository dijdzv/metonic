///|
extern "C" fn initialize_uia(reserved : UInt64, kind : UInt) -> Int = "CoInitializeEx"

///|
extern "C" fn uninitialize_uia() -> Unit = "CoUninitialize"

///|
#borrow(result)
extern "C" fn node_from_handle(
  window : UInt64,
  result : FixedArray[UInt64],
) -> Int = "UiaNodeFromHandle"

///|
extern "C" fn release_node(node : UInt64) -> Int = "UiaNodeRelease"

///|
#borrow(value)
extern "C" fn node_property(
  node : UInt64,
  id : Int,
  value : FixedArray[UInt64],
) -> Int = "UiaGetPropertyValue"

///|
#borrow(value)
extern "C" fn clear_variant(value : FixedArray[UInt64]) -> Int = "VariantClear"

///|
extern "C" fn bstr_length(value : UInt64) -> UInt = "SysStringLen"

///|
#borrow(output)
extern "C" fn copy_utf16(
  output : FixedArray[Byte],
  pointer : UInt64,
  length : UInt64,
) -> Unit = "RtlMoveMemory"

///|
#borrow(result)
extern "C" fn pattern_provider(
  node : UInt64,
  id : Int,
  result : FixedArray[UInt64],
) -> Int = "UiaGetPatternProvider"

///|
extern "C" fn release_pattern(provider : UInt64) -> Int = "UiaPatternRelease"

///|
extern "C" fn invoke_pattern(provider : UInt64) -> Int = "InvokePattern_Invoke"

///|
#borrow(value)
extern "C" fn set_value_pattern(
  provider : UInt64,
  value : FixedArray[Byte],
) -> Int = "ValuePattern_SetValue"

///|
#borrow(index, output)
extern "C" fn array_number(
  array : UInt64,
  index : FixedArray[Int],
  output : FixedArray[Double],
) -> Int = "SafeArrayGetElement"

///|
fn utf16z(value : String) -> FixedArray[Byte] {
  let bytes = FixedArray::make(value.length() * 2 + 2, b'\x00')
  for index in 0..<value.length() {
    let unit = value[index].to_int()
    bytes[index * 2] = (unit & 255).to_byte()
    bytes[index * 2 + 1] = (unit >> 8).to_byte()
  }
  bytes
}

///|
fn property_is(node : UInt64, id : Int, expected : String) -> Bool {
  let value = FixedArray::make(3, 0UL)
  if node_property(node, id, value) != 0 {
    return false
  }
  defer ignore(clear_variant(value))
  if value[0] != 8UL ||
    bstr_length(value[1]).reinterpret_as_int() != expected.length() {
    return false
  }
  let bytes = FixedArray::make(expected.length() * 2, b'\x00')
  copy_utf16(bytes, value[1], bytes.length().to_uint64())
  for index in 0..<expected.length() {
    let unit = expected[index].to_int()
    if bytes[index * 2].to_int() != (unit & 255) ||
      bytes[index * 2 + 1].to_int() != unit >> 8 {
      return false
    }
  }
  true
}

///|
fn memo_name(node : UInt64) -> Bool {
  let value = FixedArray::make(3, 0UL)
  if node_property(node, 30005, value) != 0 {
    return false
  }
  defer ignore(clear_variant(value))
  guard value[0] == 8UL else { return false }
  let length = bstr_length(value[1]).reinterpret_as_int()
  guard length >= 6 else { return false }
  let bytes = FixedArray::make(7 * 2, b'\x00')
  copy_utf16(bytes, value[1], (length.min(7) * 2).to_uint64())
  let offset = if bytes[0] == b'*' && bytes[2] == b' ' { 2 } else { 0 }
  length >= offset + 6 &&
  bytes[offset * 2] == b'M' &&
  bytes[(offset + 1) * 2] == b'e' &&
  bytes[(offset + 2) * 2] == b'm' &&
  bytes[(offset + 3) * 2] == b'o' &&
  bytes[(offset + 4) * 2] == b' '
}

///|
fn uia_root(window : UInt64) -> UInt64 raise {
  let result = FixedArray::make(1, 0UL)
  assert_eq(node_from_handle(window, result), 0)
  assert_true(result[0] != 0UL)
  result[0]
}

///|
fn uia_find(root : UInt64, name : String) -> UInt64 raise {
  let mut node = @uia.navigate(root, 3)
  for _ in 0..<1200 {
    if node == 0UL {
      return 0UL
    }
    if property_is(node, 30005, name) {
      return node
    }
    let next = @uia.navigate(node, 1)
    ignore(release_node(node))
    node = next
  }
  if node != 0UL {
    ignore(release_node(node))
  }
  fail("UIA child search exceeded the 1,000-memo bound")
}

///|
fn uia_memo_count(root : UInt64) -> Int raise {
  let mut count = 0
  let mut node = @uia.navigate(root, 3)
  for _ in 0..<1200 {
    if node == 0UL {
      return count
    }
    if memo_name(node) {
      count += 1
    }
    let next = @uia.navigate(node, 1)
    ignore(release_node(node))
    node = next
  }
  if node != 0UL {
    ignore(release_node(node))
  }
  fail("UIA memo count exceeded the 1,000-memo bound")
}

///|
fn uia_value_is(
  window : UInt64,
  name : String,
  expected : String,
) -> Bool raise {
  let root = uia_root(window)
  defer ignore(release_node(root))
  let node = uia_find(root, name)
  guard node != 0UL else { return false }
  defer ignore(release_node(node))
  property_is(node, 30045, expected)
}

///|
fn uia_memos(window : UInt64) -> Int raise {
  let root = uia_root(window)
  defer ignore(release_node(root))
  uia_memo_count(root)
}

///|
fn uia_name_exists(window : UInt64, name : String) -> Bool raise {
  let root = uia_root(window)
  defer ignore(release_node(root))
  let node = uia_find(root, name)
  if node == 0UL {
    return false
  }
  ignore(release_node(node))
  true
}

///|
fn uia_set_value(window : UInt64, name : String, value : String) -> Unit raise {
  let root = uia_root(window)
  defer ignore(release_node(root))
  let node = uia_find(root, name)
  assert_true(node != 0UL, msg="UIA input missing: " + name)
  defer ignore(release_node(node))
  let provider = FixedArray::make(1, 0UL)
  assert_eq(pattern_provider(node, 10002, provider), 0)
  assert_true(provider[0] != 0UL)
  defer ignore(release_pattern(provider[0]))
  assert_eq(set_value_pattern(provider[0], utf16z(value)), 0)
}

///|
fn uia_invoke(window : UInt64, name : String) -> Unit raise {
  let root = uia_root(window)
  defer ignore(release_node(root))
  let node = uia_find(root, name)
  assert_true(node != 0UL, msg="UIA button missing: " + name)
  defer ignore(release_node(node))
  let provider = FixedArray::make(1, 0UL)
  assert_eq(pattern_provider(node, 10000, provider), 0)
  assert_true(provider[0] != 0UL)
  defer ignore(release_pattern(provider[0]))
  assert_eq(invoke_pattern(provider[0]), 0)
}

///|
fn uia_y(window : UInt64, name : String) -> Double raise {
  let root = uia_root(window)
  defer ignore(release_node(root))
  let node = uia_find(root, name)
  assert_true(node != 0UL, msg="UIA row missing: " + name)
  defer ignore(release_node(node))
  let value = FixedArray::make(3, 0UL)
  assert_eq(node_property(node, 30001, value), 0)
  defer ignore(clear_variant(value))
  if value[0] != 8197UL {
    return -1.0
  }
  let output = FixedArray::make(1, 0.0)
  assert_eq(array_number(value[1], FixedArray::make(1, 1), output), 0)
  output[0]
}
