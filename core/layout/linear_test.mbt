///|
fn assert_linear_bounds(bounds : Array[@view.Bounds]) -> Unit raise {
  for child in bounds {
    assert_true(child.width > 0)
    assert_true(child.height > 0)
    assert_true(child.width <= 1024)
    assert_true(child.height <= 1024)
  }
  for left_index = 0; left_index < bounds.length(); left_index = left_index + 1 {
    for right_index = left_index + 1
        right_index < bounds.length()
        right_index = right_index + 1 {
      assert_eq(bounds[left_index].intersection(bounds[right_index]), None)
    }
  }
}

///|
test "linear layout places fixed and weighted fill tracks horizontally" {
  let result = layout_linear(
    axis=Horizontal,
    bounds={ x: 10, y: 20, width: 320, height: 360, },
    tracks=[
      Fixed(48),
      Fill(weight=1, min=32, max=200),
      Fill(weight=2, min=24, max=300),
    ],
    gap=8,
    padding={ top: 10, right: 12, bottom: 14, left: 8, },
  ).unwrap()
  assert_linear_bounds(result)
  assert_eq(result[0], { x: 18, y: 30, width: 48, height: 336, })
  assert_eq(result[0].x + result[0].width + 8, result[1].x)
  assert_eq(result[1].x + result[1].width + 8, result[2].x)
  assert_eq(result[1].width, 79)
  assert_eq(result[2].width, 157)
  assert_true(result[1].width >= 32 && result[1].width <= 200)
  assert_true(result[2].width >= 24 && result[2].width <= 300)
  assert_eq(result[2].x + result[2].width, 318)
}

///|
test "linear layout places vertical tracks within padded 320 by 360 bounds" {
  let result = layout_linear(
    axis=Vertical,
    bounds={ x: 10, y: 20, width: 320, height: 360, },
    tracks=[
      Fixed(40),
      Fill(weight=1, min=30, max=100),
      Fill(weight=2, min=20, max=250),
    ],
    gap=8,
    padding={ top: 10, right: 12, bottom: 14, left: 8, },
  ).unwrap()
  assert_linear_bounds(result)
  assert_eq(result[0], { x: 18, y: 30, width: 300, height: 40, })
  assert_eq(result[0].y + result[0].height + 8, result[1].y)
  assert_eq(result[1].y + result[1].height + 8, result[2].y)
  assert_eq(result[1].height, 93)
  assert_eq(result[2].height, 187)
  assert_true(result[1].height >= 30 && result[1].height <= 100)
  assert_true(result[2].height >= 20 && result[2].height <= 250)
  assert_eq(result[2].y + result[2].height, 366)
}

///|
test "linear root accepts 2048 square while fill leaves stay at 1024 maximum" {
  let result = layout_linear(
    axis=Vertical,
    bounds={ x: 0, y: 0, width: 2048, height: 2048, },
    tracks=[Fill(weight=1, min=64, max=512), Fill(weight=1, min=64, max=512)],
  ).unwrap()
  assert_linear_bounds(result)
  assert_eq(result[0], { x: 0, y: 0, width: 1024, height: 512, })
  assert_eq(result[1], { x: 0, y: 512, width: 1024, height: 512, })
  assert_true(result[1].y + result[1].height < 2048)
}

///|
test "linear container areas retain full width for nested drawable tracks" {
  let outer = layout_linear(
    axis=Vertical,
    bounds={ x: 0, y: 0, width: 2048, height: 900, },
    tracks=[Fixed(48), Fill(weight=1, min=200, max=804), Fixed(48)],
    areas=Container,
  ).unwrap()
  assert_eq(outer[1], { x: 0, y: 48, width: 2048, height: 804, })
  let body = layout_linear(
    axis=Horizontal,
    bounds=outer[1],
    tracks=[Fixed(240), Fill(weight=1, min=320, max=1024)],
    gap=16,
  ).unwrap()
  assert_eq(body[0], { x: 0, y: 48, width: 240, height: 804, })
  assert_eq(body[1], { x: 256, y: 48, width: 1024, height: 804, })
  assert_linear_bounds(body)
}

///|
test "linear fill tracks redistribute space after minimum and maximum clamps" {
  let minimum = layout_linear(
    axis=Horizontal,
    bounds={ x: 0, y: 0, width: 300, height: 80, },
    tracks=[Fill(weight=1, min=200, max=300), Fill(weight=1, min=20, max=300)],
  ).unwrap()
  assert_eq(minimum[0].width, 200)
  assert_eq(minimum[1].width, 100)
  let maximum = layout_linear(
    axis=Horizontal,
    bounds={ x: 0, y: 0, width: 300, height: 80, },
    tracks=[Fill(weight=1, min=10, max=50), Fill(weight=1, min=10, max=300)],
  ).unwrap()
  assert_eq(maximum[0].width, 50)
  assert_eq(maximum[1].width, 250)
}

///|
test "linear layout reports insufficient space instead of shrinking fixed or fill minima" {
  assert_eq(
    layout_linear(
      axis=Horizontal,
      bounds={ x: 0, y: 0, width: 97, height: 80, },
      tracks=[Fixed(60), Fill(weight=1, min=30, max=80)],
      gap=8,
    ),
    Err("insufficient_linear_space"),
  )
  assert_eq(
    layout_linear(
      axis=Horizontal,
      bounds={ x: 0, y: 0, width: 100, height: 80, },
      tracks=[Fixed(80), Fixed(30)],
    ),
    Err("insufficient_linear_space"),
  )
}

///|
test "linear layout rejects invalid track and bounds constraints" {
  assert_eq(
    layout_linear(
      axis=Horizontal,
      bounds={ x: 0, y: 0, width: 320, height: 360, },
      tracks=[Fill(weight=1, min=10, max=1025)],
    ),
    Err("invalid_linear_track"),
  )
  assert_eq(
    layout_linear(
      axis=Vertical,
      bounds={ x: 0, y: 0, width: 2049, height: 360, },
      tracks=[Fixed(32)],
    ),
    Err("invalid_linear_bounds"),
  )
}
