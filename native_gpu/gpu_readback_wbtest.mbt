///|
async test "gpu readback success timeout cleanup and recovery" {
  let instance = @wgpu.Instance::create()
  defer instance.release()
  let adapter = instance.request_adapter_sync_options_u32(
    backend_type_u32=@wgpu.BACKEND_TYPE_D3_D12,
    force_fallback_adapter=@env.get_env_var("METONIC_GPU_FALLBACK") == Some("1"),
  )
  defer adapter.release()
  let device = adapter.request_device_sync(instance)
  defer device.release()
  let queue = device.queue()
  defer queue.release()
  let registry : Map[Int, ReadbackTicket] = Map([])
  let usage = @wgpu.BufferUsage::from_u64(
    @wgpu.BUFFER_USAGE_MAP_READ | @wgpu.BUFFER_USAGE_COPY_DST,
  )
  let source_usage = @wgpu.BufferUsage::from_u64(
    @wgpu.BUFFER_USAGE_COPY_SRC | @wgpu.BUFFER_USAGE_COPY_DST,
  )
  let bytes = b"success!"
  let source = device.create_buffer(size=8UL, usage=source_usage)
  defer source.release()
  let target = device.create_buffer(size=8UL, usage~)
  defer target.release()
  queue.write_buffer(source, 0UL, bytes)
  let encoder = device.create_command_encoder()
  defer encoder.release()
  encoder.copy_buffer_to_buffer(source, 0UL, target, 0UL, 8UL)
  let command = encoder.finish()
  defer command.release()
  assert_eq(
    read_gpu_buffer(
      instance, device, queue, command, target, 0UL, 8UL, registry, 1,
    ),
    bytes,
  )
  assert_true(registry.is_empty(), msg="success ticket retained")

  let timeout_source = device.create_buffer(size=8UL, usage=source_usage)
  defer timeout_source.release()
  let timeout_target = device.create_buffer(size=8UL, usage~)
  defer timeout_target.release()
  queue.write_buffer(timeout_source, 0UL, bytes)
  let timeout_encoder = device.create_command_encoder()
  defer timeout_encoder.release()
  timeout_encoder.copy_buffer_to_buffer(
    timeout_source, 0UL, timeout_target, 0UL, 8UL,
  )
  let timeout_command = timeout_encoder.finish()
  defer timeout_command.release()
  let mut timed_out = false
  ignore(
    read_gpu_buffer(
      instance,
      device,
      queue,
      timeout_command,
      timeout_target,
      0UL,
      8UL,
      registry,
      2,
      poll_limit=0,
    ),
  ) catch {
    ReadbackTimeout => timed_out = true
    _ => fail("unexpected readback timeout error")
  }
  assert_true(timed_out, msg="readback did not timeout")
  assert_true(registry.is_empty(), msg="timeout ticket retained")

  let recovery_bytes = b"recover!"
  let recovery_source = device.create_buffer(size=8UL, usage=source_usage)
  defer recovery_source.release()
  let recovery_target = device.create_buffer(size=8UL, usage~)
  defer recovery_target.release()
  queue.write_buffer(recovery_source, 0UL, recovery_bytes)
  let recovery_encoder = device.create_command_encoder()
  defer recovery_encoder.release()
  recovery_encoder.copy_buffer_to_buffer(
    recovery_source, 0UL, recovery_target, 0UL, 8UL,
  )
  let recovery_command = recovery_encoder.finish()
  defer recovery_command.release()
  assert_eq(
    read_gpu_buffer(
      instance, device, queue, recovery_command, recovery_target, 0UL, 8UL, registry,
      3,
    ),
    recovery_bytes,
  )
  assert_true(registry.is_empty(), msg="recovery ticket retained")
}
