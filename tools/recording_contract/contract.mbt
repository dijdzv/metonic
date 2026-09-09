///|
priv struct Artifacts {
  samples : Int
  images : Int
  truncated : Bool
} derive(FromJson)

///|
priv struct Result {
  mode : String
  frames : Int
  width : Int
  height : Int
  elapsedMs : Int
  stopReason : String
  frameArtifacts : Artifacts
} derive(FromJson)

///|
priv struct Timing {
  sampleCount : Int
  imageCount : Int
} derive(FromJson)

///|
priv struct FrameInfo {
  width : Int
  height : Int
  truncated : Bool
  index : String
  format : String
} derive(FromJson)

///|
priv struct Manifest {
  schemaVersion : Int
  status : String
  stopReason : String
  timing : Timing
  frames : FrameInfo
} derive(FromJson)

///|
priv struct Sample {
  sampleIndex : Int
  elapsedMs : Int
  imageIndex : Int
  file : String
  changed : Bool
} derive(FromJson)

///|
pub struct Evidence {
  mode : String
  width : Int
  height : Int
  samples : Int
  files : Array[String]
}

///|
pub fn validate(
  result : Json,
  manifest : Json,
  samples : Array[Json],
) -> Evidence raise {
  let result : Result = @json.from_json(result)
  let manifest : Manifest = @json.from_json(manifest)
  assert_true(result.mode == "wgc" || result.mode == "printwindow")
  assert_eq(result.stopReason, "duration_elapsed")
  assert_true(result.width > 0 && result.width <= 4096)
  assert_true(result.height > 0 && result.height <= 4096)
  assert_true(result.elapsedMs > 0 && result.elapsedMs <= 15000)
  assert_true(samples.length() >= 1 && samples.length() <= 30)
  assert_eq(result.frames, samples.length())
  assert_eq(result.frameArtifacts.samples, samples.length())
  assert_false(result.frameArtifacts.truncated)
  assert_eq(manifest.schemaVersion, 1)
  assert_eq(manifest.status, "complete")
  assert_eq(manifest.stopReason, result.stopReason)
  assert_eq(manifest.timing.sampleCount, samples.length())
  assert_eq(manifest.frames.width, result.width)
  assert_eq(manifest.frames.height, result.height)
  assert_false(manifest.frames.truncated)
  assert_eq(manifest.frames.index, "frames.ndjson")
  assert_eq(manifest.frames.format, "jpeg")
  let files : Array[String] = []
  let mut previous_time = -1
  for index, raw in samples {
    let sample : Sample = @json.from_json(raw)
    assert_eq(sample.sampleIndex, index)
    assert_true(
      sample.elapsedMs >= previous_time && sample.elapsedMs <= result.elapsedMs,
    )
    assert_true(sample.elapsedMs >= 0)
    previous_time = sample.elapsedMs
    assert_true(sample.file.has_prefix("frames/frame-"))
    assert_true(sample.file.has_suffix(".jpg"))
    for ch in sample.file {
      assert_true(
        (ch >= '0' && ch <= '9') || "frames/t-.jpg".contains(ch.to_string()),
      )
    }
    assert_false(sample.file.contains(".."))
    assert_false(sample.file.contains("//"))
    assert_eq(sample.file.split("/").to_array().length(), 2)
    if sample.changed {
      assert_eq(sample.imageIndex, files.length())
      assert_false(files.contains(sample.file))
      files.push(sample.file)
    } else {
      assert_true(!files.is_empty())
      assert_eq(sample.imageIndex, files.length() - 1)
      assert_eq(sample.file, files[files.length() - 1])
    }
  }
  assert_eq(result.frameArtifacts.images, files.length())
  assert_eq(manifest.timing.imageCount, files.length())
  {
    mode: result.mode,
    width: result.width,
    height: result.height,
    samples: samples.length(),
    files,
  }
}
