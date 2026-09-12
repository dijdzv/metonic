///|
struct QueryScenario {
  mut stage : Int
  mut original : String?
  mut polls : Int
  text : String
  mut expected : String
}

///|
async fn query_pixels(view : @ui.Observation) -> Unit {
  require(
    view.query_caret_position is Some((x, y)) &&
    view.ime_position == Some((232 + x - view.query_scroll, 106 + y)),
    "IME position differs from scrolled caret",
  )
  let width = ((view.scene)(6) - 16).max(1).min(640) - 232
  let font = @fs.read_file(".work/text-assets/NotoSansJP.ttf").binary()
  let engine = @raster.create(font).unwrap()
  let expected = @raster.render(
    engine,
    view.query.value,
    width,
    32,
    selection=(view.query.selection_start, view.query.selection_end),
    caret=if view.query.selection_start == view.query.selection_end {
      Some(@semantics.caret(view.query))
    } else {
      None
    },
    single_line_scroll=Some(view.query_scroll),
  )
  let pixels = (view.capture)()
  let frame_width = (view.scene)(6)
  for y in 0..<28 {
    for x in 0..<width {
      for channel in 0..<3 {
        let actual = pixels[((106 + y) * frame_width + 232 + x) * 4 + channel].to_int()
        let linear = expected[(y * width + x) * 4 + channel].to_int()
        let reference = if view.capture_srgb {
          let value = linear.to_double() / 255.0
          ((if value <= 0.0031308 {
            value * 12.92
          } else {
            1.055 * @math.pow(value, 1.0 / 2.4) - 0.055
          }) *
          255.0 +
          0.5).to_int()
        } else {
          linear
        }
        require(
          (actual - reference).abs() <= 1,
          "query pixels differ x=" +
          x.to_string() +
          " y=" +
          y.to_string() +
          " actual=" +
          actual.to_string() +
          " expected=" +
          reference.to_string(),
        )
      }
    }
  }
}

///|
async fn QueryScenario::step(
  self : QueryScenario,
  view : @ui.Observation,
) -> Unit {
  if !view.has_renderer {
    return
  }
  self.polls += 1
  require(
    self.polls < 100,
    "query stage=" +
    self.stage.to_string() +
    " value=" +
    view.query.value +
    " caret=" +
    @semantics.caret(view.query).to_string(),
  )
  if self.original is Some(original) {
    require(view.editor.value == original, "query editing modified Text")
  }
  match self.stage {
    0 => {
      self.original = Some(view.editor.value)
      self.stage = 1
      post(view.hwnd, 0x0201U, 1UL, 115L * 65536L + 240L)
      post(view.hwnd, 0x0202U, 0UL, 115L * 65536L + 240L)
      post(view.hwnd, 0x0100U, 0x23UL, 0L)
      post(view.hwnd, 0x0100U, 0x08UL, 0L)
      for i in 0..<self.text.length() {
        post(view.hwnd, 0x0102U, self.text[i].to_int().to_uint64(), 0L)
      }
    }
    1 if view.query.value == self.text => {
      require(view.query_scroll > 0, "long query did not scroll")
      require(view.query_caret_position is Some((_, 0)), "query wrapped")
      query_pixels(view)
      self.stage = 20
      post(view.hwnd, 0x0100U, 0x76UL, 0L)
    }
    20 if view.rpc_result == "\nRPC: domain:not_found" => {
      require(view.query.value == self.text, "request changed full query")
      query_pixels(view)
      self.stage = 2
      post(view.hwnd, 0x0100U, 0x24UL, 0L)
    }
    2 if @semantics.caret(view.query) == 0 => {
      require(view.query_scroll == 0, "Home did not restore left edge")
      query_pixels(view)
      self.stage = 3
      post(view.hwnd, 0x0100U, 0x23UL, 0L)
    }
    3 if @semantics.caret(view.query) == self.text.length() => {
      require(view.query_scroll > 0, "End did not restore right edge")
      query_pixels(view)
      self.stage = 4
      (view.resize)(400, 300)
    }
    4 if (view.scene)(6) == 400 => {
      require(
        view.query_caret_position is Some((x, 0)) &&
        x - view.query_scroll == 151,
        "resize lost visible caret",
      )
      query_pixels(view)
      self.stage = 5
      post(view.hwnd, 0x0201U, 1UL, 115L * 65536L + 233L)
      post(view.hwnd, 0x0202U, 0UL, 115L * 65536L + 233L)
    }
    5 if @semantics.caret(view.query) < self.text.length() => {
      require(
        @semantics.caret(view.query) > 0,
        "scrolled pointer hit unscrolled origin",
      )
      query_pixels(view)
      self.stage = 6
      let caret = @semantics.caret(view.query)
      self.expected = self.text[:caret - 1].to_owned() +
        self.text[caret:].to_owned()
      post(view.hwnd, 0x0100U, 0x08UL, 0L)
    }
    6 if view.query.value == self.expected => {
      query_pixels(view)
      self.stage = 7
      require(
        (view.select_query)(0, self.expected.length()) == "",
        "forward query selection rejected",
      )
      (view.draw)()
    }
    7 if view.query.selection_start == 0 &&
      view.query.selection_end == self.expected.length() => {
      require(view.query_scroll > 0, "forward selection lost right edge")
      query_pixels(view)
      self.stage = 8
      require(
        (view.select_query)(self.expected.length(), 0) == "",
        "backward query selection rejected",
      )
      (view.draw)()
    }
    8 if @semantics.caret(view.query) == 0 => {
      require(
        view.query_scroll == 0,
        "reversed selection did not restore left edge",
      )
      query_pixels(view)
      self.stage = 9
      post(view.hwnd, 0x0102U, 0x78UL, 0L)
    }
    9 if view.query.value == "x" => {
      require(view.query_scroll == 0, "short replacement retained scroll")
      query_pixels(view)
      self.stage = 10
      (view.inject)(@ui.Injected::CompositionStart)
      (view.inject)(
        @ui.Injected::CompositionUpdate(self.text, Some(self.text.length())),
      )
    }
    10 if view.composing => {
      require(view.query.value == "x", "preedit changed committed query")
      require(view.query_scroll > 0, "long preedit did not scroll")
      require(
        view.query_caret_position is Some((x, 0)) &&
        view.ime_position == Some((232 + x - view.query_scroll, 106)),
        "preedit IME position differs from scrolled caret",
      )
      self.stage = 11
      (view.inject)(@ui.Injected::CompositionCancel)
    }
    11 if !view.composing => {
      require(
        view.query.value == "x" && view.query_scroll == 0,
        "cancel did not restore query viewport",
      )
      query_pixels(view)
      self.stage = 12
      println("WINDOW_QUERY_SCROLL_OK")
      (view.inject)(@ui.Injected::Close)
    }
    _ => ()
  }
}
