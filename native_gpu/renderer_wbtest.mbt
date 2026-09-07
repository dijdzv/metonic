///|
fn assert_frame(
  bytes : Bytes,
  width : Int,
  height : Int,
  x : Int,
  y : Int,
  rw : Int,
  rh : Int,
  active : Int,
) -> Unit raise Error {
  assert_eq(bytes.length(), width * height * 4)
  let mut py = 0
  while py < height {
    let mut px = 0
    while px < width {
      let inside = px >= x && px < x + rw && py >= y && py < y + rh
      let expected = if !inside {
        [5, 20, 38, 255]
      } else if active == 1 {
        [242, 97, 26, 255]
      } else {
        [20, 166, 173, 255]
      }
      let base = (py * width + px) * 4
      let mut channel = 0
      while channel < 4 {
        assert_true(
          (bytes[base + channel].to_int() - expected[channel]).abs() <= 1,
          msg="renderer pixel mismatch",
        )
        channel += 1
      }
      px += 1
    }
    py += 1
  }
}

///|
async test "persistent renderer whitebox lifecycle" {
  let fallback = @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1")
  let renderer = Renderer::new(fallback, Initialization::new())
  defer renderer.close()
  let adapter_name = renderer.adapter_name()
  assert_true(adapter_name.length() > 0, msg="missing adapter name")
  assert_true(!renderer.is_poisoned(), msg="new renderer poisoned")

  let initial = renderer.render(640, 360, 260, 144, 120, 72, 0)
  assert_frame(initial, 640, 360, 260, 144, 120, 72, 0)
  let moved = renderer.render(640, 360, 10, 20, 120, 72, 1)
  assert_frame(moved, 640, 360, 10, 20, 120, 72, 1)
  let resized = renderer.render(317, 193, 197, 121, 120, 72, 1)
  assert_frame(resized, 317, 193, 197, 121, 120, 72, 1)
  let tiny = renderer.render(1, 1, 0, 0, 1, 1, 0)
  assert_frame(tiny, 1, 1, 0, 0, 1, 1, 0)
  assert_true(!renderer.is_poisoned(), msg="renderer poisoned after renders")

  try {
    let _ = renderer.render(0, 1, 0, 0, 1, 1, 0)
  } catch {
    RendererInvalidDimensions => ()
    _ => fail("wrong error for invalid dimensions")
  } noraise {
    _ => fail("invalid dimensions were accepted")
  }
  try {
    let _ = renderer.render(8, 8, 8, 0, 1, 1, 0)
  } catch {
    RendererInvalidRectangle => ()
    _ => fail("wrong error for invalid rectangle")
  } noraise {
    _ => fail("invalid rectangle was accepted")
  }
  try {
    let _ = renderer.render(8, 8, 0, 0, 1, 1, 2)
  } catch {
    RendererInvalidRectangle => ()
    _ => fail("wrong error for invalid active")
  } noraise {
    _ => fail("invalid active was accepted")
  }
  let valid_after_errors = renderer.render(1, 1, 0, 0, 1, 1, 0)
  assert_frame(valid_after_errors, 1, 1, 0, 0, 1, 1, 0)

  renderer.close()
  renderer.close()
  assert_true(renderer.is_poisoned(), msg="closed renderer not poisoned")
  assert_eq(renderer.adapter_name(), adapter_name)
  try {
    let _ = renderer.render(1, 1, 0, 0, 1, 1, 0)
  } catch {
    RendererClosed => ()
    _ => fail("wrong error after close")
  } noraise {
    _ => fail("render after close was accepted")
  }
}
