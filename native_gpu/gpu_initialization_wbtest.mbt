///|
async test "gpu initialization async success timeout and recovery" {
  @async.with_timeout(10000, async fn() {
    let instance = @wgpu.Instance::create()
    defer instance.release()
    let owner = Initialization::new()
    let fallback = @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1")

    let adapter = initialize_adapter(owner, instance, fallback)
    defer adapter.release()
    assert_eq(adapter.info_backend_type_u32(), @wgpu.BACKEND_TYPE_D3_D12)
    assert_eq(owner.pending_count(), 0)
    let device = initialize_device(owner, instance, adapter)
    defer device.release()
    let queue = device.queue()
    defer queue.release()
    assert_eq(owner.pending_count(), 0)

    let timeout_owner = Initialization::new()
    let timed_out = try {
      let failed = initialize_adapter(
        timeout_owner,
        instance,
        fallback,
        poll_limit=0,
      )
      failed.release()
      false
    } catch {
      InitializationTimeout => true
      _ => false
    } noraise {
      _ => false
    }
    assert_true(timed_out)
    assert_eq(timeout_owner.pending_count(), 0)
    let recovered = initialize_adapter(timeout_owner, instance, fallback)
    defer recovered.release()
    assert_eq(timeout_owner.pending_count(), 0)
    let device_timed_out = try {
      let failed = initialize_device(
        timeout_owner,
        instance,
        recovered,
        poll_limit=0,
      )
      failed.release()
      false
    } catch {
      InitializationTimeout => true
      _ => false
    } noraise {
      _ => false
    }
    assert_true(device_timed_out)
    assert_eq(timeout_owner.pending_count(), 0)
    let recovered_device = initialize_device(timeout_owner, instance, recovered)
    defer recovered_device.release()
    let recovered_queue = recovered_device.queue()
    defer recovered_queue.release()
    assert_eq(timeout_owner.pending_count(), 0)
  })
}
