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
fn inside(state : @scene.State, x : Int, y : Int) -> Bool {
  x >= @scene.field(state, 0) &&
  x < @scene.field(state, 0) + @scene.field(state, 2) &&
  y >= @scene.field(state, 1) &&
  y < @scene.field(state, 1) + @scene.field(state, 3)
}

///|
async fn main {
  let state = @scene.create()
  let created = metonic_window_create()
  if created != 0 {
    println("WINDOW_CREATE_FAILED")
    metonic_window_destroy()
  } else {
    let is_test = metonic_window_test_mode() == 1
    let instance = @wgpu.Instance::create()
    let surface = instance.create_surface_windows_hwnd(
      metonic_window_hinstance(),
      metonic_window_hwnd(),
    )
    let owner = @gpu.Initialization::new()
    let renderer_ref : Ref[@gpu.SurfaceRenderer?] = { val: None, }
    let mut renderer : @gpu.SurfaceRenderer? = None
    let failed_ref : Ref[Bool] = { val: false, }
    let frames_ref : Ref[Int] = { val: 0, }
    let stage_ref : Ref[Int] = { val: 0, }
    defer {
      if owner.pending_count() != 0 {
        abort("pending initialization prevents HWND destruction")
      }
      match renderer_ref.val {
        Some(value) => value.close()
        None => ()
      }
      surface.release()
      instance.release()
      metonic_window_destroy()
    }
    let force_fallback = @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1")
    @async.with_task_group() <| group => {
      let init_task = group.spawn() <| () => {
        let value = @gpu.SurfaceRenderer::new(
          instance, surface, force_fallback, owner,
        )
        renderer_ref.val = Some(value)
        value
      }
      let mut running = true
      let mut failed = false
      let mut frames = 0
      let mut stage = 0
      let mut initialized = false
      while running && !failed {
        @async.sleep(1)
        if !initialized {
          match init_task.try_wait() {
            Some(_) => {
              ignore(init_task.wait())
              renderer = renderer_ref.val
              initialized = renderer is Some(_)
              if !initialized {
                failed = true
              } else {
                match renderer {
                  Some(value) => {
                    value.present(
                      @scene.field(state, 6),
                      @scene.field(state, 7),
                      @scene.field(state, 0),
                      @scene.field(state, 1),
                      @scene.field(state, 2),
                      @scene.field(state, 3),
                      @scene.field(state, 4),
                    )
                    frames += 1
                  }
                  None => failed = true
                }
                if is_test && metonic_window_test_step(0, 0, 0) != 0 {
                  failed = true
                }
              }
            }
            None => ()
          }
        }
        let event = metonic_window_poll_event()
        if event == -1 {
          failed = true
        } else if event == 5 {
          if is_test && stage == 3 {
            stage = 4
          }
          running = false
        } else if event == 1 {
          match renderer {
            Some(value) => {
              value.present(
                @scene.field(state, 6),
                @scene.field(state, 7),
                @scene.field(state, 0),
                @scene.field(state, 1),
                @scene.field(state, 2),
                @scene.field(state, 3),
                @scene.field(state, 4),
              )
              frames += 1
            }
            None => ()
          }
        } else if event == 2 {
          let changed = @scene.resize(
            state,
            metonic_window_event_x(),
            metonic_window_event_y(),
          )
          if changed {
            match renderer {
              Some(value) => {
                value.present(
                  @scene.field(state, 6),
                  @scene.field(state, 7),
                  @scene.field(state, 0),
                  @scene.field(state, 1),
                  @scene.field(state, 2),
                  @scene.field(state, 3),
                  @scene.field(state, 4),
                )
                frames += 1
              }
              None => ()
            }
          }
          if is_test &&
            stage == 1 &&
            @scene.field(state, 6) == 317 &&
            @scene.field(state, 7) == 193 {
            stage = 2
            if metonic_window_test_step(
                2,
                @scene.field(state, 0) + 1,
                @scene.field(state, 1) + 1,
              ) !=
              0 {
              failed = true
            }
          }
        } else if event == 3 || event == 4 {
          let key = metonic_window_event_x()
          let mut changed = false
          if event == 3 {
            if key == 37 {
              changed = @scene.move_to(
                state,
                @scene.field(state, 0) - 10,
                @scene.field(state, 1),
              )
            } else if key == 38 {
              changed = @scene.move_to(
                state,
                @scene.field(state, 0),
                @scene.field(state, 1) - 10,
              )
            } else if key == 39 {
              changed = @scene.move_to(
                state,
                @scene.field(state, 0) + 10,
                @scene.field(state, 1),
              )
            } else if key == 40 {
              changed = @scene.move_to(
                state,
                @scene.field(state, 0),
                @scene.field(state, 1) + 10,
              )
            } else if key == 32 || key == 13 {
              @scene.activate(state)
              changed = true
            }
          } else if inside(
              state,
              metonic_window_event_x(),
              metonic_window_event_y(),
            ) {
            @scene.activate(state)
            changed = true
          }
          if changed {
            match renderer {
              Some(value) => {
                value.present(
                  @scene.field(state, 6),
                  @scene.field(state, 7),
                  @scene.field(state, 0),
                  @scene.field(state, 1),
                  @scene.field(state, 2),
                  @scene.field(state, 3),
                  @scene.field(state, 4),
                )
                frames += 1
              }
              None => ()
            }
          }
          if is_test && stage == 0 && @scene.field(state, 0) == 270 {
            stage = 1
            if metonic_window_test_step(1, 0, 0) != 0 {
              failed = true
            }
          } else if is_test && stage == 2 && @scene.field(state, 4) == 1 {
            stage = 3
            if metonic_window_test_step(3, 0, 0) != 0 {
              failed = true
            }
          }
        }
      }
      if !running || failed {
        if !initialized {
          init_task.cancel()
          ignore(init_task.wait()) catch {
            error => if !@async.is_cancellation_error(error) { raise error }
          }
        }
      }
      failed_ref.val = failed
      frames_ref.val = frames
      stage_ref.val = stage
    }
    let failed = failed_ref.val
    let frames = frames_ref.val
    let stage = stage_ref.val
    if is_test {
      if !failed &&
        stage == 4 &&
        frames >= 3 &&
        @scene.field(state, 4) == 1 &&
        @scene.field(state, 6) == 317 &&
        @scene.field(state, 7) == 193 {
        println("WINDOW_PROBE_OK")
      } else {
        println("WINDOW_PROBE_FAILED")
      }
    }
  }
}
