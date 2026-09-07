///|
struct Scenario {
  mode : String
  mut retained : Bool
  mut polls : Int
  mut stage : Int
  mut canceled_id : Int
  mut scene_revision : Int
}

///|
extern "C" fn post_message(
  hwnd : UInt64,
  message : UInt,
  wparam : UInt64,
  lparam : Int64,
) -> Int = "PostMessageW"

///|
fn require(ok : Bool, message : String) -> Unit raise Error {
  guard ok else { fail(message) }
}

///|
fn post(
  hwnd : UInt64,
  message : UInt,
  wparam : UInt64,
  lparam : Int64,
) -> Unit raise Error {
  require(
    post_message(hwnd, message, wparam, lparam) != 0,
    "PostMessage failed",
  )
}

///|
async fn Scenario::step(self : Scenario, view : @ui.Observation) -> Unit {
  if self.stage == 0 && (view.scene)(0) == 270 {
    self.stage = 1
    (view.resize)(317, 193)
  } else if self.stage == 1 && (view.scene)(6) == 317 && (view.scene)(7) == 193 {
    self.stage = 2
    let packed = (((view.scene)(1) + 1) << 16) | ((view.scene)(0) + 1)
    post(view.hwnd, 0x0201U, 1UL, packed.to_int64())
  } else if self.stage == 2 && (view.scene)(4) == 1 {
    self.stage = 20
    post(view.hwnd, 0x0102U, 1UL, 0L)
    post(view.hwnd, 0x0100U, 0x24UL, 0L)
  } else if self.stage == 20 && view.editor.selection_start == 0 {
    require(
      view.editor.value == "日本語の描画を確認します ABC 123",
      "control character entered editor",
    )
    self.stage = 21
    post(view.hwnd, 0x0100U, 0x23UL, 0L)
  } else if self.stage == 21 &&
    view.editor.selection_start == view.editor.value.length() {
    self.stage = 22
    post(view.hwnd, 0x0201U, 1UL, ((16 << 16) | 8).to_int64())
  } else if self.stage == 22 && view.editor.selection_start == 0 {
    self.stage = 23
    require((view.set_text)("A😀語") == "", "navigation text rejected")
    require((view.select)(3, 3) == "", "navigation selection rejected")
    post(view.hwnd, 0x0100U, 0x25UL, 0L)
  } else if self.stage == 23 && view.editor.selection_start == 1 {
    require(
      view.editor.selection_end == 1,
      "left split supplementary character",
    )
    self.stage = 24
    post(view.hwnd, 0x0100U, 0x27UL, 0L)
  } else if self.stage == 24 && view.editor.selection_start == 3 {
    require(
      view.editor.selection_end == 3,
      "right split supplementary character",
    )
    self.stage = 25
    self.scene_revision = (view.scene)(5)
    post(view.hwnd, 0x0100U, 0x20UL, 0L)
    post(view.hwnd, 0x0100U, 0x0DUL, 0L)
    post(view.hwnd, 0x0100U, 0x26UL, 0L)
  } else if self.stage == 25 && view.editor.value == "A😀 語" {
    require((view.scene)(5) == self.scene_revision, "editing changed the scene")
    require(view.editor.focused, "typing lost editor focus")
    self.stage = 26
    post(view.hwnd, 0x0100U, 0x09UL, 0L)
    post(view.hwnd, 0x0100U, 0x0DUL, 0L)
    post(view.hwnd, 0x0100U, 0x20UL, 0L)
    post(view.hwnd, 0x0100U, 0x08UL, 0L)
  } else if self.stage == 26 && (view.scene)(5) == self.scene_revision + 2 {
    require(!view.editor.focused, "scene activation stole editor focus")
    require(view.editor.value == "A😀 語", "scene keys edited text")
    self.stage = 27
    post(view.hwnd, 0x0100U, 0x09UL, 0L)
  } else if self.stage == 27 && view.editor.focused {
    self.stage = 30
    require(
      (view.set_text)("日本語の描画を確認します ABC 123") == "",
      "editor restore rejected",
    )
    require((view.select)(0, 3) == "", "test selection rejected")
    (view.inject)(CompositionStart)
    (view.inject)(CompositionUpdate("にほん", Some(1)))
  } else if self.stage == 30 &&
    view.rendered_text == Some("にほんの描画を確認します ABC 123") {
    let node = view.editor
    require(
      node.value == "日本語の描画を確認します ABC 123",
      "preedit mutated committed text",
    )
    require(
      node.selection_start == 0 && node.selection_end == 3,
      "preedit changed selection",
    )
    require(view.preedit_cursor == 1, "composition cursor was lost")
    self.stage = 32
    (view.inject)(AccessibilityValue("must not replace composition"))
    post(view.hwnd, 0x0100U, 0x0DUL, 0L)
    post(view.hwnd, 0x0100U, 0x26UL, 0L)
  } else if self.stage == 32 {
    require(view.composing, "scene shortcut interrupted composition")
    require(
      view.editor.value == "日本語の描画を確認します ABC 123",
      "accessibility mutation replaced composition",
    )
    require(
      (view.scene)(5) == self.scene_revision + 2,
      "composition key changed the scene",
    )
    self.stage = 31
    (view.inject)(CompositionCancel)
  } else if self.stage == 31 &&
    view.rendered_text == Some("日本語の描画を確認します ABC 123") {
    require(!view.composing, "composition survived cancellation")
    self.stage = 3
    post(view.hwnd, 0x0102U, 0x8A9EUL, 0L)
    post(view.hwnd, 0x0102U, 0xD83DUL, 0L)
    post(view.hwnd, 0x0102U, 0xDE00UL, 0L)
  } else if self.stage == 3 &&
    view.editor.value == "語😀の描画を確認します ABC 123" {
    let node = view.editor
    require(
      node.selection_start == 3 && node.selection_end == 3,
      "committed text caret mismatch",
    )
    require(
      view.rendered_text == Some(node.value),
      "committed text was not rendered",
    )
    self.stage = 4
    post(view.hwnd, 0x0100U, 0x08UL, 0L)
  } else if self.stage == 4 &&
    view.editor.value == "語の描画を確認します ABC 123" {
    require(view.editor.selection_start == 1, "backspace caret mismatch")
    self.stage = 5
    let pixels = (view.capture)()
    let mut dark = 0
    for y in 8..<104 {
      for x in 8..<309 {
        let offset = (y * 317 + x) * 4
        require(pixels[offset + 3] == 255, "text capture alpha mismatch")
        if pixels[offset] < 128 &&
          pixels[offset + 1] < 128 &&
          pixels[offset + 2] < 128 {
          dark += 1
        }
      }
    }
    require(dark > 100, "text capture has no glyphs")
    require((view.set_text)("") == "", "empty text rejected")
    (view.draw)()
    let empty = (view.capture)()
    for y in 8..<104 {
      for x in 8..<309 {
        let offset = (y * 317 + x) * 4
        for channel in 0..<4 {
          let expected = if x == 8 && y < 40 && channel < 3 { 0 } else { 255 }
          require(
            empty[offset + channel].to_int() == expected,
            "empty editor must show only its insertion caret",
          )
        }
      }
    }
    post(view.hwnd, 0x0100U, 0x74UL, 0L)
    post(view.hwnd, 0x0100U, 0x74UL, 0L)
    post(view.hwnd, 0x0102U, 0x41UL, 0L)
  } else if self.stage == 5 && view.editor.value == "A" {
    require((view.task)(0) == 1, "text input did not precede delayed update")
    self.stage = 6
    (view.inject)(Updated((view.task)(1) - 1, 0))
  } else if self.stage == 6 && (view.task)(0) == 2 {
    require(
      (view.scene)(0) == (view.task)(2),
      "delayed result did not update scene",
    )
    self.stage = 7
    require(view.rejected_updates == 1, "stale result was accepted")
    post(view.hwnd, 0x0100U, 0x74UL, 0L)
  } else if self.stage == 7 && (view.task)(0) == 1 {
    self.canceled_id = (view.task)(1)
    self.stage = 8
    post(view.hwnd, 0x0100U, 0x75UL, 0L)
  } else if self.stage == 8 && (view.task)(0) == 4 {
    self.stage = 9
    (view.inject)(Updated(self.canceled_id, 0))
  } else if self.stage == 9 && view.rejected_updates == 2 {
    require((view.scene)(0) == (view.task)(2), "rejected result changed scene")
    self.stage = 10
    post(view.hwnd, 0x0100U, 0x74UL, 0L)
    post(view.hwnd, 0x0010U, 0UL, 0L)
  }
}

///|
fn Scenario::finish(
  self : Scenario,
  mode : String,
  view : @ui.Observation,
) -> Unit raise Error {
  if mode != "normal" {
    require(self.retained, "initialization event not observed")
    println("WINDOW_INIT_REMAINING=" + view.pending_initialization.to_string())
  }
  if mode == "close" {
    require(
      view.frames == 0 && !view.has_renderer && view.pending_initialization == 0,
      "initialization close failed",
    )
    println("WINDOW_INIT_CLOSE_OK")
  } else {
    require(
      self.stage == 10 &&
      view.frames >= 3 &&
      (view.scene)(4) == 1 &&
      (view.scene)(6) == 317 &&
      (view.scene)(7) == 193,
      "window scenario failed",
    )
    println(
      if mode == "input" {
        "WINDOW_INIT_INPUT_OK"
      } else {
        "WINDOW_PROBE_OK"
      },
    )
  }
}

///|
fn Scenario::lifecycle(
  self : Scenario,
  phase : @ui.Lifecycle,
  view : @ui.Observation,
) -> Bool raise Error {
  match phase {
    Starting if self.mode != "normal" => {
      require(
        view.pending_initialization > 0,
        "initialization ticket not retained",
      )
      post(
        view.hwnd,
        if self.mode == "input" {
          0x0100U
        } else {
          0x0010U
        },
        0x27UL,
        0L,
      )
    }
    InputHandled if self.mode == "input" && !self.retained => {
      require(
        (view.scene)(0) == 270,
        "initialization input did not update scene",
      )
      require(
        view.pending_initialization > 0,
        "host event arrived after initialization ownership released",
      )
      self.retained = true
      println("WINDOW_INIT_RETAINED=" + view.pending_initialization.to_string())
    }
    Closing if self.mode == "close" && !self.retained => {
      require(
        view.pending_initialization > 0,
        "host event arrived after initialization ownership released",
      )
      self.retained = true
      println("WINDOW_INIT_RETAINED=" + view.pending_initialization.to_string())
    }
    Ready => {
      if self.mode == "input" {
        require((view.scene)(0) == 270, "first frame lost initialization input")
      }
      if self.mode == "normal" {
        post(view.hwnd, 0x0100U, 0x27UL, 0L)
      }
    }
    Poll => {
      self.polls += 1
      require(self.polls <= 64, "initialization host event poll limit exceeded")
    }
    _ => ()
  }
  self.mode == "normal" || self.retained
}
