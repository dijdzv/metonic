///|
fn fixture() -> (Json, Json, Array[Json]) {
  (
    {
      "mode": "wgc",
      "frames": 2,
      "width": 642,
      "height": 392,
      "elapsedMs": 1005,
      "stopReason": "duration_elapsed",
      "frameArtifacts": { "samples": 2, "images": 1, "truncated": false },
    },
    {
      "schemaVersion": 1,
      "status": "complete",
      "stopReason": "duration_elapsed",
      "timing": { "sampleCount": 2, "imageCount": 1 },
      "frames": {
        "width": 642,
        "height": 392,
        "truncated": false,
        "index": "frames.ndjson",
        "format": "jpeg",
      },
    },
    [
      {
        "sampleIndex": 0,
        "elapsedMs": 1,
        "imageIndex": 0,
        "file": "frames/frame-000000-t000000000001.jpg",
        "changed": true,
      },
      {
        "sampleIndex": 1,
        "elapsedMs": 499,
        "imageIndex": 0,
        "file": "frames/frame-000000-t000000000001.jpg",
        "changed": false,
      },
    ],
  )
}

///|
fn changed(value : Json, key : String, replacement : Json) -> Json {
  guard value is Json::Object(fields) else { abort("fixture object required") }
  let copied = fields.copy()
  copied[key] = replacement
  Json::object(copied)
}

///|
test "complete samples retain actual capture mode and repeated image identity" {
  let (result, manifest, samples) = fixture()
  let evidence = validate(result, manifest, samples)
  assert_eq(evidence.mode, "wgc")
  assert_eq(evidence.files.length(), 1)
  assert_eq(
    validate(changed(result, "mode", "printwindow"), manifest, samples).mode,
    "printwindow",
  )
}

///|
test "incomplete or unrelated recording cannot supply window provenance" {
  let (result, manifest, samples) = fixture()
  for
    change in [
      ("mode", Json::string("screen")),
      ("frames", Json::number(3)),
      ("stopReason", Json::string("window_closed")),
      ("elapsedMs", Json::number(0)),
    ] {
    let (key, value) = change
    let rejected = try {
      ignore(validate(changed(result, key, value), manifest, samples))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  let rejected = try {
    ignore(validate(result, changed(manifest, "status", "partial"), samples))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "sample ordering and paths cannot be forged by a valid completion envelope" {
  let (result, manifest, samples) = fixture()
  for
    change in [
      ("elapsedMs", Json::number(0)),
      ("file", Json::string("frames/../outside.jpg")),
      ("imageIndex", Json::number(1)),
      ("sampleIndex", Json::number(0)),
    ] {
    let (key, value) = change
    let altered = [samples[0], changed(samples[1], key, value)]
    let rejected = try {
      ignore(validate(result, manifest, altered))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "truncated artifacts and mismatched dimensions are rejected" {
  let (result, manifest, samples) = fixture()
  let truncated : Json = { "samples": 2, "images": 1, "truncated": true }
  let rejected = try {
    ignore(
      validate(changed(result, "frameArtifacts", truncated), manifest, samples),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let wrong : Json = {
    "width": 640,
    "height": 392,
    "truncated": false,
    "index": "frames.ndjson",
    "format": "jpeg",
  }
  let rejected = try {
    ignore(validate(result, changed(manifest, "frames", wrong), samples))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
