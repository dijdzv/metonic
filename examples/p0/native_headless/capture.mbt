///|
/// Capture writes the renderer's tightly packed RGBA bytes to the configured path.
fn absolute_capture_path(path : String) -> Bool {
  let chars = path.to_array()
  let drive = chars.length() >= 3 &&
    (
      (chars[0] >= 'A' && chars[0] <= 'Z') ||
      (chars[0] >= 'a' && chars[0] <= 'z')
    ) &&
    chars[1] == ':' &&
    (chars[2] == '\\' || chars[2] == '/')
  let unc = chars.length() >= 2 && chars[0] == '\\' && chars[1] == '\\'
  drive || unc
}

///|
async fn capture(
  renderer : Ref[@gpu.Renderer?],
  width : Int,
  height : Int,
  x : Int,
  y : Int,
  w : Int,
  h : Int,
  active : Int,
) -> Int raise Error {
  let path = match @env.get_env_var("METONIC_CAPTURE_PATH") {
    Some(value) if absolute_capture_path(value) => value
    _ => return -1
  }
  let gpu = match renderer.val {
    Some(value) => value
    None => {
      let value = @gpu.Renderer::new(
        @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1"),
      ) catch {
        error => {
          if @async.is_cancellation_error(error) {
            raise error
          }
          return -1
        }
      }
      renderer.val = Some(value)
      @stdio.stderr.write("backend=dx12 adapter=" + value.adapter_name() + "\n") catch {
        error => if @async.is_cancellation_error(error) { raise error }
      }
      value
    }
  }
  try {
    let pixels = gpu.render(width, height, x, y, w, h, active)
    @fs.write_file(path, pixels)
    0
  } catch {
    error => {
      if @async.is_cancellation_error(error) {
        raise error
      }
      -1
    }
  }
}
