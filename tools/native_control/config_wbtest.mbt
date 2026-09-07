///|
fn expect_config_failure(config : Config, expected : String) -> Bool {
  try {
    validate_config(config)
    false
  } catch {
    ClientError::Failure(message) => message == expected
    _ => false
  }
}

///|
test "native control config validates bridge-free and invalid contracts" {
  let valid = Config::new("C:/fixture.exe", [], "C:/capture.rgba", 1, 1)
  validate_config(valid)
  assert_true(
    expect_config_failure(
      Config::new("fixture.exe", [], "C:/capture.rgba", 1, 1),
      "executable must be absolute",
    ),
  )
  assert_true(
    expect_config_failure(
      Config::new("C:/fixture.exe", [], "capture.rgba", 1, 1),
      "capture_path must be absolute",
    ),
  )
  assert_true(
    expect_config_failure(
      Config::new("C:/fixture.exe", [], "C:/capture.rgba", 0, 1),
      "timeout_ms must be positive",
    ),
  )
  assert_true(
    expect_config_failure(
      Config::new("C:/fixture.exe", [], "C:/capture.rgba", 1, 0),
      "max_pending must be positive",
    ),
  )
}
