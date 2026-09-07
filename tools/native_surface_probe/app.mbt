///|
extern "C" fn metonic_window_create() -> Int = "metonic_window_create"

///|
extern "C" fn metonic_window_next_event() -> Int = "metonic_window_next_event"

///|
extern "C" fn metonic_window_test_mode() -> Int = "metonic_window_test_mode"

///|
extern "C" fn metonic_window_test_step(step : Int, x : Int, y : Int) -> Int = "metonic_window_test_step"

///|
extern "C" fn metonic_window_event_x() -> Int = "metonic_window_event_x"

///|
extern "C" fn metonic_window_event_y() -> Int = "metonic_window_event_y"

///|
extern "C" fn metonic_window_destroy() -> Unit = "metonic_window_destroy"

///|
extern "C" fn metonic_binding_hwnd() -> @c.OpaquePtr = "metonic_binding_hwnd"

///|
extern "C" fn metonic_binding_hinstance() -> @c.OpaquePtr = "metonic_binding_hinstance"

///|
fn expect_error(action : () -> Unit raise Error, message : String) -> Unit {
  let failed = try {
    action()
    false
  } catch {
    _ => true
  } noraise {
    _ => false
  }
  if !failed {
    abort(message)
  }
}

///|
async fn stage(name : String) -> Unit {
  @stdio.stderr.write("SURFACE_STAGE=" + name + "\n") catch {
    _ => ()
  }
}

///|
async fn main {
  stage("init")
  if @env.get_env_var("METONIC_WINDOW_TEST") != Some("1") {
    abort("METONIC_WINDOW_TEST=1 is required")
  }
  if metonic_window_create() != 0 || metonic_window_test_mode() != 1 {
    abort("window creation failed")
  }
  if @env.get_env_var("METONIC_SURFACE_RAW") == Some("1") {
    raw_probe()
    metonic_window_destroy()
    return
  }
  let instance = @wgpu.Instance::create()
  let surface = instance.create_surface_windows_hwnd(
    metonic_binding_hinstance(),
    metonic_binding_hwnd(),
  )
  let surfaces : Ref[@wgpu.Surface?] = { val: Some(surface), }
  let owner = @gpu.Initialization::new()
  let mut renderer : @gpu.SurfaceRenderer? = None
  defer {
    if owner.pending_count() != 0 {
      abort("pending initialization prevents HWND destruction")
    }
    match renderer {
      Some(value) => value.close()
      None => ()
    }
    match surfaces.val {
      Some(value) => value.release()
      None => ()
    }
    instance.release()
    metonic_window_destroy()
  }
  let force_fallback = @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1")
  let initial_surface = match surfaces.val {
    Some(value) => value
    None => abort("missing initial surface")
  }
  let first = @gpu.SurfaceRenderer::new(
    instance, initial_surface, force_fallback, owner,
  )
  renderer = Some(first)
  let active_renderer = match renderer {
    Some(value) => value
    None => abort("renderer initialization failed")
  }
  stage("initial-present")
  active_renderer.present(640, 360, 260, 144, 120, 72, 0)
  stage("invalid-inputs")
  expect_error(
    () => active_renderer.present(0, 360, 260, 144, 120, 72, 0),
    "invalid width accepted",
  )
  expect_error(
    () => active_renderer.present(2049, 360, 260, 144, 120, 72, 0),
    "oversized width accepted",
  )
  expect_error(
    () => active_renderer.present(640, 360, 600, 300, 120, 72, 0),
    "invalid rectangle accepted",
  )
  stage("active-present")
  active_renderer.present(640, 360, 260, 144, 120, 72, 1)

  let resized = metonic_window_test_step(1, 0, 0) == 0
  let mut resize_seen = false
  let mut event_count = 0
  while resized && !resize_seen && event_count < 64 {
    let event = metonic_window_next_event()
    event_count += 1
    if event == 2 {
      resize_seen = metonic_window_event_x() == 317 &&
        metonic_window_event_y() == 193
    }
  }
  if !resize_seen {
    abort("resize event not observed")
  }
  stage("resize-present")
  active_renderer.present(317, 193, 10, 20, 120, 72, 1)

  stage("close-first")
  active_renderer.close()
  active_renderer.close()
  expect_error(
    () => active_renderer.present(317, 193, 10, 20, 120, 72, 1),
    "closed renderer accepted present",
  )
  renderer = None
  let mut generation = 0
  let mut adapter_name = ""
  while generation < 2 {
    stage("recreate-" + generation.to_string())
    match surfaces.val {
      Some(value) => {
        surfaces.val = None
        value.release()
      }
      None => abort("missing surface before fresh recreation")
    }
    let fresh_surface = instance.create_surface_windows_hwnd(
      metonic_binding_hinstance(),
      metonic_binding_hwnd(),
    )
    surfaces.val = Some(fresh_surface)
    let recovery_surface = match surfaces.val {
      Some(value) => value
      None => abort("missing recovery surface")
    }
    let recovered = @gpu.SurfaceRenderer::new(
      instance, recovery_surface, force_fallback, owner,
    )
    renderer = Some(recovered)
    stage("recovered-present-" + generation.to_string())
    recovered.present(317, 193, 10, 20, 120, 72, 1)
    if owner.pending_count() != 0 {
      abort("recovery left pending initialization")
    }
    stage("close-recovered-" + generation.to_string())
    recovered.close()
    recovered.close()
    expect_error(
      () => recovered.present(317, 193, 10, 20, 120, 72, 1),
      "closed renderer accepted present",
    )
    adapter_name = recovered.adapter_name()
    renderer = None
    generation += 1
  }
  println("SURFACE_RENDERER_ADAPTER=" + adapter_name)
  println("SURFACE_RENDERER_OK")
}
