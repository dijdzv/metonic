///|
extern "C" fn metonic_window_create() -> Int = "metonic_window_create"

///|
extern "C" fn metonic_window_poll_event() -> Int = "metonic_window_poll_event"

///|
extern "C" fn metonic_window_event_x() -> Int = "metonic_window_event_x"

///|
extern "C" fn metonic_window_event_y() -> Int = "metonic_window_event_y"

///|
extern "C" fn metonic_window_test_mode() -> Int = "metonic_window_test_mode"

///|
extern "C" fn metonic_window_test_step(step : Int, x : Int, y : Int) -> Int = "metonic_window_test_step"

///|
extern "C" fn metonic_window_destroy() -> Unit = "metonic_window_destroy"

///|
extern "C" fn metonic_window_hwnd() -> @c.OpaquePtr = "metonic_window_hwnd"

///|
extern "C" fn metonic_window_hinstance() -> @c.OpaquePtr = "metonic_window_hinstance"

///|
extern "C" fn metonic_async_start(
  id : Int,
  delay : Int,
  value : Int,
  fail : Int,
) -> Int = "metonic_async_start"

///|
extern "C" fn metonic_async_pending() -> Int = "metonic_async_pending"

///|
extern "C" fn metonic_async_shutdown() -> Unit = "metonic_async_shutdown"

///|
extern "C" fn metonic_async_shutdown_elapsed() -> Int = "metonic_async_shutdown_elapsed"

///|
fn draw(renderer : @gpu.SurfaceRenderer, s : @scene.State) -> Bool {
  try {
    renderer.present(
      @scene.field(s, 6),
      @scene.field(s, 7),
      @scene.field(s, 0),
      @scene.field(s, 1),
      @scene.field(s, 2),
      @scene.field(s, 3),
      @scene.field(s, 4),
    )
    true
  } catch {
    _ => false
  }
}

///|
fn draw_if(renderer : @gpu.SurfaceRenderer?, s : @scene.State) -> Bool {
  match renderer {
    Some(value) => draw(value, s)
    None => false
  }
}

///|
async fn main {
  let s = @scene.create()
  let scope = @task_scope.create()
  let mut failed = false
  let mut closed = false
  let mut responsive = false
  let mut rejected = 0
  let mut stage = 0
  let mut renderer : @gpu.SurfaceRenderer? = None
  let shutdown_done : Ref[Bool] = { val: false, }
  if metonic_window_create() != 0 || metonic_window_test_mode() != 1 {
    failed = true
  } else {
    let instance = @wgpu.Instance::create()
    let surface = instance.create_surface_windows_hwnd(
      metonic_window_hinstance(),
      metonic_window_hwnd(),
    )
    let owner = @gpu.Initialization::new()
    defer {
      if !shutdown_done.val {
        metonic_async_shutdown()
        shutdown_done.val = true
      }
      if metonic_async_pending() != 0 {
        abort("worker shutdown left pending tasks")
      }
      if owner.pending_count() != 0 {
        abort("pending initialization prevents HWND destruction")
      }
      match renderer {
        Some(value) => value.close()
        None => ()
      }
      surface.release()
      instance.release()
      metonic_window_destroy()
    }
    let value = @gpu.SurfaceRenderer::new(
      instance,
      surface,
      @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1"),
      owner,
    )
    renderer = Some(value)
    if !draw(value, s) || metonic_window_test_step(0, 0, 0) != 0 {
      failed = true
    }
    if !failed {
      let first = @task_scope.begin(scope)
      if first != 1 || metonic_async_start(1, 200, 40, 0) != 0 {
        failed = true
      }
    }
    while !failed && !closed {
      @async.sleep(1)
      let e = metonic_window_poll_event()
      if e == -1 {
        failed = true
      } else if e == 5 {
        if stage == 6 {
          closed = true
        } else {
          failed = true
        }
      } else if e == 1 {
        if !draw_if(renderer, s) {
          failed = true
        }
      } else if e == 2 {
        ignore(
          @scene.resize(s, metonic_window_event_x(), metonic_window_event_y()),
        )
        if !draw_if(renderer, s) {
          failed = true
        }
      } else if e == 3 && metonic_window_event_x() == 39 && stage == 0 {
        if @task_scope.field(scope, 0) != 1 ||
          responsive ||
          @scene.field(s, 0) != 260 ||
          !@scene.move_to(s, 270, @scene.field(s, 1)) ||
          !draw_if(renderer, s) {
          failed = true
        } else {
          responsive = true
        }
      } else if e == 6 &&
        stage == 0 &&
        metonic_window_event_x() == 1 &&
        metonic_window_event_y() == 40 {
        if !responsive ||
          !@task_scope.complete(scope, 1, 40) ||
          !@scene.move_to(s, 40, @scene.field(s, 1)) ||
          !draw_if(renderer, s) {
          failed = true
        } else {
          let old = @task_scope.begin(scope)
          let fresh = @task_scope.begin(scope)
          if old != 2 ||
            fresh != 3 ||
            metonic_async_start(old, 300, 50, 0) != 0 ||
            metonic_async_start(fresh, 20, 90, 0) != 0 {
            failed = true
          } else {
            stage = 1
          }
        }
      } else if e == 6 &&
        stage == 1 &&
        metonic_window_event_x() == 3 &&
        metonic_window_event_y() == 90 {
        if !@task_scope.complete(scope, 3, 90) ||
          !@scene.move_to(s, 90, @scene.field(s, 1)) ||
          !draw_if(renderer, s) {
          failed = true
        } else {
          stage = 2
        }
      } else if e == 6 &&
        stage == 2 &&
        metonic_window_event_x() == 2 &&
        metonic_window_event_y() == 50 {
        if @task_scope.complete(scope, 2, 50) ||
          @task_scope.field(scope, 0) != 2 ||
          @scene.field(s, 0) != 90 {
          failed = true
        } else {
          rejected += 1
          let id = @task_scope.begin(scope)
          if id != 4 ||
            metonic_async_start(id, 20, 110, 0) != 0 ||
            !@task_scope.cancel(scope) {
            failed = true
          } else {
            stage = 3
          }
        }
      } else if e == 6 &&
        stage == 3 &&
        metonic_window_event_x() == 4 &&
        metonic_window_event_y() == 110 {
        if @task_scope.complete(scope, 4, 110) ||
          @task_scope.field(scope, 0) != 4 ||
          @scene.field(s, 0) != 90 {
          failed = true
        } else {
          rejected += 1
          let id = @task_scope.begin(scope)
          if id != 5 || metonic_async_start(id, 20, 7, 1) != 0 {
            failed = true
          } else {
            stage = 4
          }
        }
      } else if e == 7 &&
        stage == 4 &&
        metonic_window_event_x() == 5 &&
        metonic_window_event_y() == 7 {
        if !@task_scope.fail(scope, 5, 7) ||
          @task_scope.field(scope, 0) != 3 ||
          @task_scope.field(scope, 3) != 7 ||
          @scene.field(s, 0) != 90 {
          failed = true
        } else {
          let id = @task_scope.begin(scope)
          if id != 6 ||
            metonic_async_start(id, 20, 120, 0) != 0 ||
            !@task_scope.dispose(scope) {
            failed = true
          } else {
            stage = 5
          }
        }
      } else if e == 6 &&
        stage == 5 &&
        metonic_window_event_x() == 6 &&
        metonic_window_event_y() == 120 {
        if @task_scope.complete(scope, 6, 120) ||
          @task_scope.field(scope, 0) != 5 ||
          @scene.field(s, 0) != 90 {
          failed = true
        } else {
          rejected += 1
          let mut i = 0
          while i < 16 {
            if metonic_async_start(1000 + i, 5000, i, 0) != 0 {
              failed = true
            }
            i += 1
          }
          if metonic_async_pending() != 16 ||
            metonic_async_start(2000, 5000, 0, 0) == 0 ||
            metonic_window_test_step(3, 0, 0) != 0 {
            failed = true
          } else {
            stage = 6
          }
        }
      } else if e == 6 || e == 7 {
        failed = true
      }
    }
    if !shutdown_done.val {
      metonic_async_shutdown()
      shutdown_done.val = true
    }
    println("NATIVE_ASYNC_SHUTDOWN_MS=\{metonic_async_shutdown_elapsed()}")
    let success = !failed &&
      closed &&
      responsive &&
      rejected == 3 &&
      stage == 6 &&
      @task_scope.field(scope, 0) == 5 &&
      @scene.field(s, 0) == 90 &&
      metonic_async_pending() == 0 &&
      metonic_async_start(3000, 20, 0, 0) != 0
    ignore(@task_scope.dispose(scope))
    if success {
      println("NATIVE_ASYNC_OK")
    } else {
      println("NATIVE_ASYNC_FAILED")
    }
  }
}
