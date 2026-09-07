///|
fn assert_sync_error(
  action : () -> Bytes raise @wgpu.BufferSyncError,
  expected : String,
  message : String,
) -> Unit raise Error {
  let result : Result[Bytes, @wgpu.BufferSyncError] = try? action()
  match result {
    Ok(_) => fail(message + ": expected BufferSyncError")
    Err(error) => assert_eq(error.message(), expected)
  }
}

///|
test "buffer sync errors recover on the same device" {
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
  let usage = @wgpu.BufferUsage::from_u64(
    @wgpu.BUFFER_USAGE_MAP_READ | @wgpu.BUFFER_USAGE_COPY_DST,
  )
  let source_usage = @wgpu.BufferUsage::from_u64(
    @wgpu.BUFFER_USAGE_COPY_SRC | @wgpu.BUFFER_USAGE_COPY_DST,
  )

  let bounded = device.create_buffer(size=16UL, usage~)
  defer bounded.release()
  assert_sync_error(
    () => bounded.readback_or_raise(instance, 17UL, 1UL),
    "buffer range is out of bounds (offset=17, size=1, buffer_size=16)",
    "out of bounds",
  )

  let alignment = device.create_buffer(size=17UL, usage~)
  defer alignment.release()
  assert_sync_error(
    () => alignment.readback_or_raise(instance, 16UL, 1UL),
    "buffer range is within bounds, but required aligned mapping exceeds buffer size (offset=16, size=1, aligned_offset=16, aligned_size=4, buffer_size=17)",
    "aligned out of bounds",
  )

  let expected = b"recover!"
  let source = device.create_buffer(size=8UL, usage=source_usage)
  defer source.release()
  let recovered = device.create_buffer(size=8UL, usage~)
  defer recovered.release()
  queue.write_buffer(source, 0UL, expected)
  let encoder = device.create_command_encoder()
  encoder.copy_buffer_to_buffer(source, 0UL, recovered, 0UL, 8UL)
  let command = encoder.finish()
  defer command.release()
  defer encoder.release()
  queue.submit_one(command)
  ignore(device.poll(wait=true))
  let output = recovered.readback_or_raise(instance, 0UL, 8UL)
  assert_eq(output, expected)

  let mut created = 0
  while created < 4 {
    let source = device.create_buffer(size=4UL, usage=source_usage)
    defer source.release()
    let buffer = device.create_buffer(size=4UL, usage~)
    defer buffer.release()
    let bytes = b"ok!!"
    queue.write_buffer(source, 0UL, bytes)
    let encoder = device.create_command_encoder()
    encoder.copy_buffer_to_buffer(source, 0UL, buffer, 0UL, 4UL)
    let command = encoder.finish()
    defer command.release()
    defer encoder.release()
    queue.submit_one(command)
    ignore(device.poll(wait=true))
    assert_eq(buffer.readback_or_raise(instance, 0UL, 4UL), bytes)
    created += 1
  }

  let second_device = adapter.request_device_sync(instance)
  defer second_device.release()
  let second_queue = second_device.queue()
  defer second_queue.release()
  let second_source = second_device.create_buffer(size=8UL, usage=source_usage)
  defer second_source.release()
  let second_buffer = second_device.create_buffer(size=8UL, usage~)
  defer second_buffer.release()
  second_queue.write_buffer(second_source, 0UL, expected)
  let second_encoder = second_device.create_command_encoder()
  second_encoder.copy_buffer_to_buffer(
    second_source, 0UL, second_buffer, 0UL, 8UL,
  )
  let second_command = second_encoder.finish()
  defer second_command.release()
  defer second_encoder.release()
  second_queue.submit_one(second_command)
  ignore(second_device.poll(wait=true))
  assert_eq(second_buffer.readback_or_raise(instance, 0UL, 8UL), expected)
}
