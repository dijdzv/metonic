///|
suberror SurfaceRendererTestFailure derive(Debug)

///|
fn fake_acquisition(
  statuses : Array[UInt],
  releases : Array[Int],
  events : Array[String],
  reconfigure_count : Ref[Int],
  reconfigure_fails : Bool,
) -> (() -> Int, (Int) -> UInt, (Int) -> Unit, () -> Unit raise Error) {
  let acquire_count : Ref[Int] = { val: 0, }
  (
    () => {
      let value = acquire_count.val
      acquire_count.val += 1
      value
    },
    id => statuses[id],
    value => {
      releases.push(value)
      events.push("release")
    },
    () => {
      reconfigure_count.val += 1
      events.push("reconfigure")
      if reconfigure_fails {
        raise SurfaceRendererTestFailure
      }
    },
  )
}

///|
test "surface acquisition preserves optimal and suboptimal ownership" {
  for
    status_code in [
      @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_OPTIMAL,
      @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_SUBOPTIMAL,
    ] {
    let releases : Array[Int] = []
    let events : Array[String] = []
    let reconfigures : Ref[Int] = { val: 0, }
    let (acquire, status, release, reconfigure) = fake_acquisition(
      [status_code],
      releases,
      events,
      reconfigures,
      false,
    )
    assert_eq(acquire_surface_texture(acquire, status, release, reconfigure), 0)
    assert_eq(releases.length(), 0)
    assert_eq(events.length(), 0)
    assert_eq(reconfigures.val, 0)
  }
}

///|
test "surface acquisition retries lost and outdated exactly once" {
  for
    case in [
      (
        @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_LOST,
        @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_OPTIMAL,
      ),
      (
        @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_OUTDATED,
        @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_SUBOPTIMAL,
      ),
    ] {
    let (initial, success) = case
    let releases : Array[Int] = []
    let events : Array[String] = []
    let reconfigures : Ref[Int] = { val: 0, }
    let (acquire, status, release, reconfigure) = fake_acquisition(
      [initial, success],
      releases,
      events,
      reconfigures,
      false,
    )
    assert_eq(acquire_surface_texture(acquire, status, release, reconfigure), 1)
    assert_eq(releases, [0])
    assert_eq(events, ["release", "reconfigure"])
    assert_eq(reconfigures.val, 1)
  }
  for
    status_code in [
      @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_LOST,
      @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_OUTDATED,
    ] {
    let releases : Array[Int] = []
    let events : Array[String] = []
    let reconfigures : Ref[Int] = { val: 0, }
    let (acquire, status, release, reconfigure) = fake_acquisition(
      [status_code, status_code],
      releases,
      events,
      reconfigures,
      false,
    )
    let actual : UInt = try {
      ignore(acquire_surface_texture(acquire, status, release, reconfigure))
      fail("repeated surface loss unexpectedly succeeded")
      0U
    } catch {
      SurfaceRendererError::SurfaceRendererAcquire(value) => value
      _ => fail("unexpected repeated surface loss error")
    } noraise {
      _ => fail("repeated surface loss raised outside expected error")
    }
    assert_eq(actual, status_code)
    assert_eq(releases, [0, 1])
    assert_eq(events, ["release", "reconfigure", "release"])
    assert_eq(reconfigures.val, 1)
  }
}

///|
test "surface acquisition terminal errors do not retry" {
  for
    status_code in [
      @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_TIMEOUT,
      @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_DEVICE_LOST,
      @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_ERROR,
    ] {
    let releases : Array[Int] = []
    let events : Array[String] = []
    let reconfigures : Ref[Int] = { val: 0, }
    let (acquire, status, release, reconfigure) = fake_acquisition(
      [status_code],
      releases,
      events,
      reconfigures,
      false,
    )
    let actual : UInt = try {
      ignore(acquire_surface_texture(acquire, status, release, reconfigure))
      fail("terminal surface error unexpectedly succeeded")
      0U
    } catch {
      SurfaceRendererError::SurfaceRendererAcquire(value) => value
      _ => fail("unexpected terminal surface error")
    } noraise {
      _ => fail("terminal surface error raised outside expected error")
    }
    assert_eq(actual, status_code)
    assert_eq(releases, [0])
    assert_eq(events, ["release"])
    assert_eq(reconfigures.val, 0)
  }
}

///|
test "surface acquisition releases before reconfigure failure" {
  let releases : Array[Int] = []
  let events : Array[String] = []
  let reconfigures : Ref[Int] = { val: 0, }
  let (acquire, status, release, reconfigure) = fake_acquisition(
    [@wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_LOST],
    releases,
    events,
    reconfigures,
    true,
  )
  let failed = try {
    ignore(acquire_surface_texture(acquire, status, release, reconfigure))
    fail("reconfigure failure unexpectedly succeeded")
    false
  } catch {
    SurfaceRendererTestFailure => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(failed)
  assert_eq(releases, [0])
  assert_eq(events, ["release", "reconfigure"])
  assert_eq(reconfigures.val, 1)
}
