///|
test "only a valid high-confidence low-score answer can omit a test" {
  let low = @json.parse(
    "{\"type\":\"score\",\"score\":0,\"confidence\":0.99,\"probabilities\":{\"0\":1,\"1\":0,\"2\":0}}",
  )
  assert_false(select(Some(low), 0.1, 0.98))
  assert_true(select(None, 0.1, 0.98))
  assert_true(select(Some(@json.parse("{}")), 0.1, 0.98))
  assert_true(select(Some(low), -1, 0.98))
  let uncertain = @json.parse(
    "{\"type\":\"score\",\"score\":0,\"confidence\":0.4,\"probabilities\":{\"0\":1,\"1\":0,\"2\":0}}",
  )
  assert_true(select(Some(uncertain), 0.1, 0.98))
  let invalid = @json.parse(
    "{\"type\":\"score\",\"score\":0,\"confidence\":1,\"probabilities\":{\"0\":0,\"1\":0,\"2\":0}}",
  )
  assert_true(select(Some(invalid), 0.1, 0.98))
}

///|
test "collection allowlist excludes credentials and hidden generated trees" {
  assert_true(allowed("core/reactive/value.mbt"))
  assert_true(allowed("core/reactive/moon.pkg"))
  for
    path in [
      ".env", ".env.local", ".work/copied.mbt", ".metonic/framework/model.mbt", "secret.key",
      "node_modules/test.mbt",
    ] {
    assert_false(allowed(path))
  }
}

///|
test "guarded four-level selection keeps uncertain and malformed answers" {
  let answer = @json.parse(
    "{\"type\":\"score\",\"score\":0.93,\"confidence\":0.07,\"probabilities\":{\"0\":0.52,\"1\":0.11,\"2\":0.29,\"3\":0.08}}",
  )
  // The unguarded reference rule missed a known affected UI test here.
  assert_false(select_four(Some(answer)))
  assert_true(select_four(Some(answer), guarded=true))
  for
    raw in [
      "null", "{}", "{\"type\":\"score\",\"score\":0,\"confidence\":1,\"probabilities\":{\"0\":1,\"1\":0,\"2\":0}}",
      "{\"type\":\"score\",\"score\":0,\"confidence\":1,\"probabilities\":{\"0\":0,\"1\":0,\"2\":0,\"3\":0}}",
    ] {
    assert_true(select_four(Some(@json.parse(raw)), guarded=true))
  }
  assert_true(select_four(None, guarded=true))
}

///|
test "guarded four-level omission requires all three evidence thresholds" {
  for
    (score, confidence, safe, expected_run) in [
      (1.99, 0.6, 0.6, false),
      (2.0, 0.6, 0.6, true),
      (1.99, 0.59, 0.6, true),
      (1.99, 0.6, 0.59, true),
    ] {
    let answer : Json = {
      "type": "score",
      "score": Json::number(score),
      "confidence": Json::number(confidence),
      "probabilities": {
        "0": Json::number(safe),
        "1": 0,
        "2": Json::number(1.0 - safe),
        "3": 0,
      },
    }
    assert_eq(select_four(Some(answer), guarded=true), expected_run)
  }
}
