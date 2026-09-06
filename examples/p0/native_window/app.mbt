///|
extern "C" fn metonic_window_create() -> Int = "metonic_window_create"

///|
extern "C" fn metonic_window_next_event() -> Int = "metonic_window_next_event"

///|
extern "C" fn metonic_window_event_x() -> Int = "metonic_window_event_x"

///|
extern "C" fn metonic_window_event_y() -> Int = "metonic_window_event_y"

///|
extern "C" fn metonic_window_render(
  width : Int,
  height : Int,
  x : Int,
  y : Int,
  w : Int,
  h : Int,
  active : Int,
) -> Int = "metonic_window_render"

///|
extern "C" fn metonic_window_test_mode() -> Int = "metonic_window_test_mode"

///|
extern "C" fn metonic_window_test_step(step : Int, x : Int, y : Int) -> Int = "metonic_window_test_step"

///|
extern "C" fn metonic_window_destroy() -> Unit = "metonic_window_destroy"

///|
fn render(state : @scene.State) -> Bool {
  metonic_window_render(
    @scene.field(state, 6),
    @scene.field(state, 7),
    @scene.field(state, 0),
    @scene.field(state, 1),
    @scene.field(state, 2),
    @scene.field(state, 3),
    @scene.field(state, 4),
  ) ==
  0
}

///|
fn inside(state : @scene.State, x : Int, y : Int) -> Bool {
  x >= @scene.field(state, 0) &&
  x < @scene.field(state, 0) + @scene.field(state, 2) &&
  y >= @scene.field(state, 1) &&
  y < @scene.field(state, 1) + @scene.field(state, 3)
}

///|
fn main {
  let state = @scene.create()
  let created = metonic_window_create()
  if created != 0 {
    println("WINDOW_CREATE_FAILED")
    metonic_window_destroy()
  } else {
    let is_test = metonic_window_test_mode() == 1
    let mut running = true
    let mut failed = false
    let mut frames = 0
    let mut stage = 0
    if is_test {
      if !render(state) {
        failed = true
      } else {
        frames += 1
      }
      if metonic_window_test_step(0, 0, 0) != 0 {
        failed = true
      }
    }
    while running && !failed {
      let event = metonic_window_next_event()
      if event == -1 {
        failed = true
      } else if event == 5 {
        if is_test && stage == 3 {
          stage = 4
        }
        running = false
      } else if event == 1 {
        if !render(state) {
          failed = true
        } else {
          frames += 1
        }
      } else if event == 2 {
        let changed = @scene.resize(
          state,
          metonic_window_event_x(),
          metonic_window_event_y(),
        )
        if changed && !render(state) {
          failed = true
        } else if changed {
          frames += 1
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
          if !render(state) {
            failed = true
          } else {
            frames += 1
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
    metonic_window_destroy()
  }
}
