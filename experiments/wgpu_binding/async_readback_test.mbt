///|
fn make_usage(parts : Array[UInt64]) -> @wgpu.BufferUsage {
  let mut value = 0UL
  for part in parts {
    value = value | part
  }
  @wgpu.BufferUsage::from_u64(value)
}

///|
fn wait_for_readback(
  instance : @wgpu.Instance,
  device : @wgpu.Device,
  queue : @wgpu.Queue,
  future_id : UInt64,
) -> UInt raise Error {
  let deadline = @env.now() + 10000
  let mut status = queue.map_read_async_status_u32(future_id)
  let mut iterations = 0
  while status == 0U && @env.now() < deadline && iterations < 100000 {
    ignore(device.poll(wait=false))
    instance.process_events()
    status = queue.map_read_async_status_u32(future_id)
    iterations += 1
  }
  assert_true(status != 0U, msg="map read remained pending")
  assert_true(@env.now() < deadline, msg="map read exceeded deadline")
  assert_true(iterations < 100000, msg="map read exceeded iteration limit")
  status
}

///|
test "async buffer readback and destroyed staging terminate" {
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

  let source = device.create_buffer(
    size=8UL,
    usage=make_usage([@wgpu.BUFFER_USAGE_COPY_SRC, @wgpu.BUFFER_USAGE_COPY_DST]),
  )
  defer source.release()
  let staging = device.create_buffer(
    size=8UL,
    usage=make_usage([@wgpu.BUFFER_USAGE_MAP_READ, @wgpu.BUFFER_USAGE_COPY_DST]),
  )
  defer staging.release()

  let first = b"async-1!"
  queue.write_buffer(source, 0UL, first)
  let encoder = device.create_command_encoder()
  defer encoder.release()
  encoder.copy_buffer_to_buffer(source, 0UL, staging, 0UL, 8UL)
  let command = encoder.finish()
  defer command.release()
  let future = queue.submit_one_and_map_read_async(command, staging, 0UL, 8UL)
  assert_true(future != 0UL, msg="first map future was not created")
  let status = wait_for_readback(instance, device, queue, future)
  assert_eq(status, @wgpu.MAP_ASYNC_STATUS_SUCCESS)
  assert_eq(queue.map_read_async_read(future), first)
  queue.map_read_async_clear(future)
  assert_eq(queue.map_read_async_status_u32(future), 0U)
  assert_eq(queue.map_read_async_read(future), [])

  let second = b"async-2!"
  queue.write_buffer(source, 0UL, second)
  let encoder2 = device.create_command_encoder()
  defer encoder2.release()
  encoder2.copy_buffer_to_buffer(source, 0UL, staging, 0UL, 8UL)
  let command2 = encoder2.finish()
  defer command2.release()
  let future2 = queue.submit_one_and_map_read_async(command2, staging, 0UL, 8UL)
  assert_true(future2 != 0UL, msg="second map future was not created")
  let status2 = wait_for_readback(instance, device, queue, future2)
  assert_eq(status2, @wgpu.MAP_ASYNC_STATUS_SUCCESS)
  assert_eq(queue.map_read_async_read(future2), second)
  queue.map_read_async_clear(future2)
  assert_eq(queue.map_read_async_status_u32(future2), 0U)
  assert_eq(queue.map_read_async_read(future2), [])

  let doomed = device.create_buffer(
    size=8UL,
    usage=make_usage([@wgpu.BUFFER_USAGE_MAP_READ, @wgpu.BUFFER_USAGE_COPY_DST]),
  )
  defer doomed.release()
  let encoder3 = device.create_command_encoder()
  defer encoder3.release()
  encoder3.copy_buffer_to_buffer(source, 0UL, doomed, 0UL, 8UL)
  let command3 = encoder3.finish()
  defer command3.release()
  let future3 = queue.submit_one_and_map_read_async(command3, doomed, 0UL, 8UL)
  assert_true(future3 != 0UL, msg="destroyed map future was not created")
  assert_eq(queue.map_read_async_status_u32(future3), 0U)
  doomed.destroy()
  assert_eq(queue.map_read_async_status_u32(future3), 0U)
  let destroyed_status = wait_for_readback(instance, device, queue, future3)
  assert_eq(destroyed_status, @wgpu.MAP_ASYNC_STATUS_ERROR)
  queue.map_read_async_clear(future3)
  assert_eq(queue.map_read_async_status_u32(future3), 0U)
  assert_eq(queue.map_read_async_read(future3), [])

  let fresh = device.create_buffer(
    size=8UL,
    usage=make_usage([@wgpu.BUFFER_USAGE_MAP_READ, @wgpu.BUFFER_USAGE_COPY_DST]),
  )
  defer fresh.release()
  let encoder4 = device.create_command_encoder()
  defer encoder4.release()
  encoder4.copy_buffer_to_buffer(source, 0UL, fresh, 0UL, 8UL)
  let command4 = encoder4.finish()
  defer command4.release()
  let future4 = queue.submit_one_and_map_read_async(command4, fresh, 0UL, 8UL)
  assert_true(future4 != 0UL, msg="fresh map future was not created")
  let fresh_status = wait_for_readback(instance, device, queue, future4)
  assert_eq(fresh_status, @wgpu.MAP_ASYNC_STATUS_SUCCESS)
  assert_eq(queue.map_read_async_read(future4), second)
  queue.map_read_async_clear(future4)
  assert_eq(queue.map_read_async_status_u32(future4), 0U)
  assert_eq(queue.map_read_async_read(future4), [])
}
