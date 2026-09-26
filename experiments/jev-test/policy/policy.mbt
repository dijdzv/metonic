///|
pub fn select(
  answer : Json?,
  max_score : Double,
  min_confidence : Double,
) -> Bool {
  guard max_score >= 0 &&
    max_score < 1 &&
    min_confidence >= 0 &&
    min_confidence <= 1 else {
    return true
  }
  guard answer is Some(Object(fields)) else { return true }
  guard fields.get("type") == Some(Json::string("score")) else { return true }
  guard fields.get("score") is Some(Number(score, ..)) &&
    fields.get("confidence") is Some(Number(confidence, ..)) else {
    return true
  }
  guard score >= 0 && score <= 2 && confidence >= 0 && confidence <= 1 else {
    return true
  }
  guard fields.get("probabilities") is Some(Object(probabilities)) else {
    return true
  }
  let mut total = 0.0
  for level in ["0", "1", "2"] {
    guard probabilities.get(level) is Some(Number(p, ..)) && p >= 0 && p <= 1 else {
      return true
    }
    total += p
  }
  guard probabilities.length() == 3 && total >= 0.999 && total <= 1.001 else {
    return true
  }
  guard probabilities.get("0") is Some(Number(p0, ..)) && p0 >= min_confidence else {
    return true
  }
  return !(score <= max_score && confidence >= min_confidence)
}

///|
pub fn allowed(path : String) -> Bool {
  let normalized = path.replace_all(old="\\", new="/")
  if normalized
    .split("/")
    .any(part => part.has_prefix(".") || part == "node_modules") {
    return false
  }
  normalized.has_suffix(".mbt") ||
  normalized.has_suffix(".mbti") ||
  normalized.has_suffix(".mbtx") ||
  normalized == "moon.mod" ||
  normalized.has_suffix("/moon.mod") ||
  normalized == "moon.pkg" ||
  normalized.has_suffix("/moon.pkg") ||
  normalized == "moon.lock" ||
  normalized.has_suffix("/moon.lock") ||
  normalized.has_suffix("/moon.work") ||
  normalized == "moon.work" ||
  normalized == "toolchain.json" ||
  normalized.has_suffix("/moon.pkg.json") ||
  normalized == "moon.pkg.json" ||
  normalized.has_suffix("/moon.mod.json") ||
  normalized == "moon.mod.json"
}

///|
pub fn select_four(answer : Json?, guarded? : Bool = false) -> Bool {
  guard answer is Some(Object(fields)) else { return true }
  guard fields.get("type") == Some(Json::string("score")) else { return true }
  guard fields.get("score") is Some(Number(score, ..)) &&
    fields.get("confidence") is Some(Number(confidence, ..)) else {
    return true
  }
  guard score >= 0 && score <= 3 && confidence >= 0 && confidence <= 1 else {
    return true
  }
  guard fields.get("probabilities") is Some(Object(probabilities)) else {
    return true
  }
  let mut total = 0.0
  for level in ["0", "1", "2", "3"] {
    guard probabilities.get(level) is Some(Number(p, ..)) && p >= 0 && p <= 1 else {
      return true
    }
    total += p
  }
  guard probabilities.length() == 4 && total >= 0.999 && total <= 1.001 else {
    return true
  }
  if guarded {
    let p0 = match probabilities["0"] {
      Number(p, ..) => p
      _ => 0.0
    }
    let p1 = match probabilities["1"] {
      Number(p, ..) => p
      _ => 0.0
    }
    score >= 2.0 || confidence < 0.6 || p0 + p1 < 0.6
  } else {
    score >= 2.0 || (score >= 1.0 && confidence < 0.5)
  }
}

///|
pub fn select_levels(answer : Json?, levels : Int) -> Bool {
  guard levels == 5 || levels == 6 else { return true }
  guard answer is Some(Object(fields)) else { return true }
  guard fields.get("type") == Some(Json::string("score")) else { return true }
  guard fields.get("score") is Some(Number(score, ..)) &&
    fields.get("confidence") is Some(Number(confidence, ..)) else {
    return true
  }
  guard score >= 0 &&
    score <= (levels - 1).to_double() &&
    confidence >= 0 &&
    confidence <= 1 else {
    return true
  }
  guard fields.get("probabilities") is Some(Object(probabilities)) else {
    return true
  }
  let mut total = 0.0
  let mut safe = 0.0
  for level in 0..<levels {
    guard probabilities.get(level.to_string()) is Some(Number(p, ..)) &&
      p >= 0 &&
      p <= 1 else {
      return true
    }
    total += p
    if level < 2 {
      safe += p
    }
  }
  guard probabilities.length() == levels && total >= 0.999 && total <= 1.001 else {
    return true
  }
  score >= 2 || confidence < 0.6 || safe < 0.6
}
