///|
fn fixture(mode : String) -> Array[String] {
  [
    "_build/wasm/release/build/tools/browser_supervisor_fixture/browser_supervisor_fixture.wasm",
    mode,
  ]
}

///|
async test "native exit stops the owned server without waiting for its lifetime" {
  @async.with_timeout(5000, () => {
    run_session(
      ".tools/moonbit/bin/moonrun.exe",
      fixture("server-ready"),
      ".tools/moonbit/bin/moonrun.exe",
      fixture("verifier-ok"),
    )
  })
}

///|
async test "unexpected server exit cancels a running native child" {
  let mut rejected = false
  @async.with_timeout(5000, () => {
    run_session(
      ".tools/moonbit/bin/moonrun.exe",
      fixture("server-exit"),
      ".tools/moonbit/bin/moonrun.exe",
      fixture("verifier-hang"),
    ) catch {
      DemoFailure::Failure(message) =>
        rejected = message == "demo server exited: 7"
      error => raise error
    }
  })
  assert_true(rejected)
}

///|
async test "wrong readiness never launches the native child" {
  let mut rejected = false
  @async.with_timeout(5000, () => {
    run_session(
      ".tools/moonbit/bin/moonrun.exe",
      fixture("server-bad"),
      "must-not-be-launched",
      [],
    ) catch {
      DemoFailure::Failure(message) =>
        rejected = message == "unexpected demo server address"
      error => raise error
    }
  })
  assert_true(rejected)
}

///|
async test "native startup failure releases the already ready server" {
  let rejected = @async.with_timeout(5000, () => {
    try
      run_session(
        ".tools/moonbit/bin/moonrun.exe",
        fixture("server-ready"),
        "missing-metonic-demo-executable",
        [],
      )
    catch {
      _ => true
    } noraise {
      _ => false
    }
  })
  assert_true(rejected)
}
