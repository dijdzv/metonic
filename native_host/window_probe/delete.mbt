///|
struct DeleteScenario {
  mut stage : Int
  mut keys : Int
}

///|
fn DeleteScenario::step(
  self : DeleteScenario,
  view : @ui.Observation,
) -> Unit raise Error {
  if !view.has_renderer {
    return
  }
  require(view.query.value == "1", "editor Delete changed User ID")
  match self.stage {
    0 => {
      self.stage = 10
      post(view.hwnd, 0x0201U, 1UL, 16L * 65536L + 16L)
      post(view.hwnd, 0x0202U, 0UL, 16L * 65536L + 16L)
    }
    10 if view.editor.focused => {
      require((view.set_text)("A😀日B") == "", "editor setup failed")
      require((view.select)(1, 1) == "", "editor selection failed")
      (view.draw)()
      self.stage = 1
      self.keys = view.input.key_presses
      post(view.hwnd, 0x0100U, 0x2EUL, 0L)
    }
    1 if view.input.key_presses > self.keys => {
      require(
        view.editor.value == "A日B",
        "Delete did not remove the supplementary character",
      )
      require(@semantics.caret(view.editor) == 1, "Delete moved caret")
      require((view.select)(1, 2) == "", "range setup failed")
      (view.draw)()
      self.stage = 2
      self.keys = view.input.key_presses
      post(view.hwnd, 0x0100U, 0x2EUL, 0L)
    }
    2 if view.input.key_presses > self.keys => {
      require(
        view.editor.value == "AB",
        "Delete did not remove the selected range",
      )
      require((view.select)(2, 2) == "", "end setup failed")
      (view.draw)()
      self.keys = view.input.key_presses
      self.stage = 3
      post(view.hwnd, 0x0100U, 0x2EUL, 0L)
    }
    3 if view.input.key_presses > self.keys => {
      require(
        view.editor.value == "AB" && @semantics.caret(view.editor) == 2,
        "Delete at end changed text",
      )
      require((view.select)(0, 1) == "", "composition selection failed")
      (view.draw)()
      self.stage = 4
      (view.inject)(@ui.Injected::CompositionStart)
      (view.inject)(@ui.Injected::CompositionUpdate("日本", Some(2)))
    }
    4 if view.composing => {
      self.keys = view.input.key_presses
      self.stage = 5
      post(view.hwnd, 0x0100U, 0x2EUL, 0L)
    }
    5 if view.input.key_presses > self.keys => {
      require(
        view.composing && view.editor.value == "B",
        "Delete altered active composition",
      )
      require(
        view.editor.selection_start == 0 && view.editor.selection_end == 0,
        "Delete changed composing selection",
      )
      self.stage = 6
      (view.inject)(@ui.Injected::CompositionCancel)
    }
    6 if !view.composing => {
      self.stage = 7
      post(view.hwnd, 0x0100U, 0x09UL, 0L)
    }
    7 if !view.editor.focused && !view.query.focused => {
      self.keys = view.input.key_presses
      self.stage = 8
      post(view.hwnd, 0x0100U, 0x2EUL, 0L)
    }
    8 if view.input.key_presses > self.keys => {
      require(view.editor.value == "B", "unfocused Delete changed text")
      self.stage = 9
      println("WINDOW_DELETE_OK")
      (view.inject)(@ui.Injected::Close)
    }
    _ => ()
  }
}
