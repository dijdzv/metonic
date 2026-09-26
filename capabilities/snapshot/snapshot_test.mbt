///|
async test "snapshot distinguishes missing, empty and unicode text" {
  let saved : Ref[String?] = Ref(None)
  let snapshot = Snapshot::new(() => Ok(saved.val), value => {
    saved.val = Some(value)
    Ok(())
  })
  assert_eq(snapshot.load(), Ok(None))
  assert_eq(snapshot.save(""), Ok(()))
  assert_eq(snapshot.load(), Ok(Some("")))
  assert_eq(snapshot.save("日本語😀"), Ok(()))
  assert_eq(snapshot.load(), Ok(Some("日本語😀")))
}

///|
async test "snapshot bounds UTF-8 bytes before writing and after reading" {
  let writes = Ref(0)
  let oversized = "あ".repeat(max_utf8_bytes() / 3 + 1)
  let snapshot = Snapshot::new(() => Ok(Some(oversized)), _ => {
    writes.val += 1
    Ok(())
  })
  assert_eq(snapshot.save(oversized), Err(TooLarge))
  assert_eq(writes.val, 0)
  assert_eq(snapshot.load(), Err(TooLarge))
}

///|
async test "snapshot rejects overlapping calls and clears busy after completion" {
  @async.with_timeout(5000, () => {
    let entered = @cond_var.Cond()
    let release = @cond_var.Cond()
    let snapshot = Snapshot::new(
      () => {
        entered.signal()
        release.wait()
        Ok(None)
      },
      _ => Ok(()),
    )
    @async.with_task_group(group => {
      let loading = group.spawn(() => snapshot.load())
      entered.wait()
      assert_eq(snapshot.save("later"), Err(Busy))
      release.signal()
      assert_eq(loading.wait(), Ok(None))
      assert_eq(snapshot.save("later"), Ok(()))
    })
  })
}

///|
async test "canceled snapshot load releases its single-flight slot" {
  @async.with_timeout(5000, () => {
    let entered = @cond_var.Cond()
    let blocked = @cond_var.Cond()
    let snapshot = Snapshot::new(
      () => {
        entered.signal()
        blocked.wait()
        Ok(None)
      },
      _ => Ok(()),
    )
    @async.with_task_group(group => {
      group.spawn_bg(() => ignore(snapshot.load()))
      entered.wait()
      group.return_immediately(())
    })
    assert_eq(snapshot.save("after cancel"), Ok(()))
  })
}

///|
async test "failed save is not reported as accepted" {
  let snapshot = Snapshot::new(() => Err(Failed), _ => Err(CapacityExceeded))
  assert_eq(snapshot.load(), Err(Failed))
  assert_eq(snapshot.save("draft"), Err(CapacityExceeded))
}

///|
async test "canceled snapshot save releases its single-flight slot" {
  @async.with_timeout(5000, () => {
    let entered = @cond_var.Cond()
    let blocked = @cond_var.Cond()
    let snapshot = Snapshot::new(() => Ok(None), _ => {
      entered.signal()
      blocked.wait()
      Ok(())
    })
    @async.with_task_group(group => {
      group.spawn_bg(() => ignore(snapshot.save("draft")))
      entered.wait()
      group.return_immediately(())
    })
    assert_eq(snapshot.load(), Ok(None))
  })
}
