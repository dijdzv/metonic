///|
/// Status zero is pending.  The future is only taken after a terminal status;
/// in particular, a timeout deliberately does not clear a pending request.
async fn wait_adapter_request(
  instance : @wgpu.Instance,
  future_id : UInt64,
) -> Unit {
  let completed = @async.with_timeout_opt(10000, () => {
    let mut status = instance.request_adapter_async_status_u32(future_id)
    let mut attempts = 0
    while status == 0U && attempts < 10000 {
      instance.process_events()
      @async.sleep(1)
      status = instance.request_adapter_async_status_u32(future_id)
      attempts += 1
    }
    status != 0U
  })
  match completed {
    Some(true) => ()
    _ => abort("DX12 adapter request remained pending")
  }
}

///|
async fn wait_device_request(
  instance : @wgpu.Instance,
  adapter : @wgpu.Adapter,
  future_id : UInt64,
) -> Unit {
  let completed = @async.with_timeout_opt(10000, () => {
    let mut status = adapter.request_device_async_status_u32(future_id)
    let mut attempts = 0
    while status == 0U && attempts < 10000 {
      instance.process_events()
      @async.sleep(1)
      status = adapter.request_device_async_status_u32(future_id)
      attempts += 1
    }
    status != 0U
  })
  match completed {
    Some(true) => ()
    _ => abort("DX12 device request remained pending")
  }
}

///|
fn force_fallback() -> Bool {
  @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1")
}

///|
fn adapter_options(
  force_fallback_adapter : Bool,
) -> @c.WGPURequestAdapterOptionsPtr {
  @c.request_adapter_options_new_u32(
    @wgpu.FEATURE_LEVEL_CORE,
    @wgpu.POWER_PREFERENCE_UNDEFINED,
    force_fallback_adapter,
    @wgpu.BACKEND_TYPE_D3_D12,
    @c.null_surface(),
  )
}

///|
async test "async DX12 adapter and device initialization can be reused" {
  let instance = @wgpu.Instance::create()
  defer instance.release()
  let fallback = force_fallback()

  let options1 = adapter_options(fallback)
  let adapter_future1 = instance.request_adapter_future_id_u64(options=options1)
  @c.request_adapter_options_free(options1)
  assert_true(adapter_future1 != 0UL, msg="adapter future was not created")
  wait_adapter_request(instance, adapter_future1)
  let adapter1 = instance.request_adapter_async_take_or_raise(adapter_future1)
  defer adapter1.release()
  assert_eq(adapter1.info_backend_type_u32(), @wgpu.BACKEND_TYPE_D3_D12)
  assert_true(adapter1.info_device().length() > 0, msg="adapter name is empty")
  let device_future1 = adapter1.request_device_future_id_u64()
  assert_true(device_future1 != 0UL, msg="device future was not created")
  wait_device_request(instance, adapter1, device_future1)
  let device1 = adapter1.request_device_async_take_or_raise(device_future1)
  defer device1.release()
  assert_eq(device1.info_backend_type_u32(), @wgpu.BACKEND_TYPE_D3_D12)
  let queue1 = device1.queue()
  defer queue1.release()

  let options2 = adapter_options(fallback)
  let adapter_future2 = instance.request_adapter_future_id_u64(options=options2)
  @c.request_adapter_options_free(options2)
  assert_true(
    adapter_future2 != 0UL,
    msg="second adapter future was not created",
  )
  wait_adapter_request(instance, adapter_future2)
  let adapter2 = instance.request_adapter_async_take_or_raise(adapter_future2)
  defer adapter2.release()
  assert_eq(adapter2.info_backend_type_u32(), @wgpu.BACKEND_TYPE_D3_D12)

  let device_future2 = adapter2.request_device_future_id_u64()
  assert_true(device_future2 != 0UL, msg="second device future was not created")
  wait_device_request(instance, adapter2, device_future2)
  let device2 = adapter2.request_device_async_take_or_raise(device_future2)
  defer device2.release()
  assert_eq(device2.info_backend_type_u32(), @wgpu.BACKEND_TYPE_D3_D12)
  let queue2 = device2.queue()
  defer queue2.release()
  println("GPU_INIT_OK adapter=" + adapter1.info_device() + " repeated=true")
}

///|
async test "async initialization can release completed results and recover" {
  let instance = @wgpu.Instance::create()
  defer instance.release()
  let options = adapter_options(force_fallback())
  let adapter_future = instance.request_adapter_future_id_u64(options~)
  @c.request_adapter_options_free(options)
  assert_true(adapter_future != 0UL, msg="adapter future was not created")
  wait_adapter_request(instance, adapter_future)
  let adapter = instance.request_adapter_async_take_or_raise(adapter_future)
  assert_eq(adapter.info_backend_type_u32(), @wgpu.BACKEND_TYPE_D3_D12)
  let device_future = adapter.request_device_future_id_u64()
  assert_true(device_future != 0UL, msg="device future was not created")
  wait_device_request(instance, adapter, device_future)
  let device = adapter.request_device_async_take_or_raise(device_future)
  assert_eq(device.info_backend_type_u32(), @wgpu.BACKEND_TYPE_D3_D12)
  let queue = device.queue()
  queue.release()
  device.release()
  adapter.release()

  let recovery_options = adapter_options(force_fallback())
  let recovery_future = instance.request_adapter_future_id_u64(
    options=recovery_options,
  )
  @c.request_adapter_options_free(recovery_options)
  assert_true(
    recovery_future != 0UL,
    msg="recovery adapter future was not created",
  )
  wait_adapter_request(instance, recovery_future)
  let recovery_adapter = instance.request_adapter_async_take_or_raise(
    recovery_future,
  )
  assert_eq(recovery_adapter.info_backend_type_u32(), @wgpu.BACKEND_TYPE_D3_D12)
  let recovery_device_future = recovery_adapter.request_device_future_id_u64()
  assert_true(
    recovery_device_future != 0UL,
    msg="recovery device future was not created",
  )
  wait_device_request(instance, recovery_adapter, recovery_device_future)
  let recovery_device = recovery_adapter.request_device_async_take_or_raise(
    recovery_device_future,
  )
  assert_eq(recovery_device.info_backend_type_u32(), @wgpu.BACKEND_TYPE_D3_D12)
  let recovery_queue = recovery_device.queue()
  recovery_queue.release()
  recovery_device.release()
  println("GPU_INIT_RECOVERY_OK adapter=" + recovery_adapter.info_device())
  recovery_adapter.release()
}
