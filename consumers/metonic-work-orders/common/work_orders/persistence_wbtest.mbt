///|
async test "missing snapshot starts a draft and only Save acknowledges it" {
  let stored : Ref[String?] = Ref(None)
  let snapshot = @snapshot.Snapshot::new(() => Ok(stored.val), text => {
    stored.val = Some(text)
    Ok(())
  })
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let persistence = Persistence::new(root, snapshot)
  persistence.connect(@task.task_control(_ => ()))
  let loaded : Ref[Array[WorkOrder]] = Ref([])
  let load = persistence.load(orders => loaded.val = orders).unwrap()
  assert_eq(persistence.phase, NotLoaded)
  load.invalidate()
  assert_eq(persistence.phase, Loading)
  assert_eq(load.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(loaded.val.length(), 3)
  assert_true(persistence.dirty())
  let save = persistence.save(loaded.val).unwrap()
  save.invalidate()
  assert_eq(save.prepare().unwrap().run().apply(), @task.Changed)
  assert_false(persistence.dirty())
  assert_eq(decode_orders(stored.val.unwrap()), Ok(loaded.val))
  root.dispose()
}

///|
async test "later edit stays unsaved after an earlier write succeeds" {
  let stored : Ref[String?] = Ref(None)
  let snapshot = @snapshot.Snapshot::new(() => Ok(stored.val), text => {
    stored.val = Some(text)
    Ok(())
  })
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let persistence = Persistence::new(root, snapshot)
  persistence.connect(@task.task_control(_ => ()))
  let loaded : Ref[Array[WorkOrder]] = Ref([])
  let load = persistence.load(orders => loaded.val = orders).unwrap()
  load.invalidate()
  ignore(load.prepare().unwrap().run().apply())
  let save = persistence.save(loaded.val).unwrap()
  save.invalidate()
  let receipt = save.prepare().unwrap().run()
  persistence.edited()
  assert_eq(receipt.apply(), @task.Changed)
  assert_eq(persistence.saved_revision, Some(1))
  assert_eq(persistence.revision, 2)
  assert_true(persistence.dirty())
  assert_eq(persistence.status(), "Unsaved changes")
  root.dispose()
}

///|
async test "malformed stored data is preserved until an explicit retry loads valid data" {
  let stored : Ref[String?] = Ref(Some("METONIC_WORK_ORDERS\n{"))
  let snapshot = @snapshot.Snapshot::new(() => Ok(stored.val), text => {
    stored.val = Some(text)
    Ok(())
  })
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let persistence = Persistence::new(root, snapshot)
  persistence.connect(@task.task_control(_ => ()))
  let loaded : Ref[Array[WorkOrder]] = Ref([])
  let first = persistence.load(orders => loaded.val = orders).unwrap()
  first.invalidate()
  ignore(first.prepare().unwrap().run().apply())
  assert_eq(persistence.phase, LoadFailed("Malformed work-order snapshot"))
  assert_eq(loaded.val.length(), 0)
  assert_eq(stored.val, Some("METONIC_WORK_ORDERS\n{"))
  stored.val = Some(encode_orders(seed_orders()))
  let retry = persistence.load(orders => loaded.val = orders).unwrap()
  retry.invalidate()
  assert_eq(retry.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(loaded.val.length(), 3)
  assert_false(persistence.dirty())
  root.dispose()
}

///|
async test "failed Save preserves draft and last snapshot for a later retry" {
  let saved : Ref[String?] = Ref(None)
  let reject : Ref[Bool] = Ref(true)
  let snapshot = @snapshot.Snapshot::new(() => Ok(saved.val), text => {
    if reject.val {
      Err(@snapshot.CapacityExceeded)
    } else {
      saved.val = Some(text)
      Ok(())
    }
  })
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let persistence = Persistence::new(root, snapshot)
  persistence.connect(@task.task_control(_ => ()))
  let loaded : Ref[Array[WorkOrder]] = Ref([])
  let load = persistence.load(orders => loaded.val = orders).unwrap()
  load.invalidate()
  ignore(load.prepare().unwrap().run().apply())
  let failed = persistence.save(loaded.val).unwrap()
  failed.invalidate()
  ignore(failed.prepare().unwrap().run().apply())
  assert_eq(saved.val, None)
  assert_true(persistence.dirty())
  assert_eq(persistence.status(), "Save failed: Storage capacity exceeded")
  reject.val = false
  let retry = persistence.save(loaded.val).unwrap()
  retry.invalidate()
  ignore(retry.prepare().unwrap().run().apply())
  assert_false(persistence.dirty())
  assert_eq(decode_orders(saved.val.unwrap()), Ok(loaded.val))
  root.dispose()
}

///|
async test "close confirmation waits for Save and can be canceled or discarded" {
  let snapshot = @snapshot.Snapshot::new(() => Ok(None), _ => Ok(()))
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let persistence = Persistence::new(root, snapshot)
  persistence.connect(@task.task_control(_ => ()))
  let load = persistence.load(_ => ()).unwrap()
  load.invalidate()
  ignore(load.prepare().unwrap().run().apply())
  persistence.request_close()
  assert_false(persistence.can_close())
  assert_false(persistence.close_ready())
  persistence.cancel_close()
  assert_false(persistence.close_ready())
  persistence.request_close()
  persistence.discard_and_close()
  assert_true(persistence.close_ready())
  assert_true(persistence.dirty())
  root.dispose()
}
