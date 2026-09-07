///|
/// Start a bounded asynchronous readback while retaining every native handle
/// captured by the ticket until the future is cleared.
pub async fn read_gpu_buffer(
  instance : @wgpu.Instance,
  device : @wgpu.Device,
  queue : @wgpu.Queue,
  command : @wgpu.CommandBuffer,
  buffer : @wgpu.Buffer,
  offset : UInt64,
  size : UInt64,
  registry : Map[Int, ReadbackTicket],
  id : Int,
  timeout_ms? : Int = 10000,
  cleanup_ms? : Int = 1000,
  poll_limit? : Int = 100000,
) -> Bytes raise Error {
  if registry.get(id) is Some(_) {
    raise ReadbackFailed(0U)
  }
  if size == 0UL ||
    offset % 8UL != 0UL ||
    size % 4UL != 0UL ||
    offset > buffer.size() ||
    size > buffer.size() - offset ||
    size > @int.MAX_VALUE.to_uint64() {
    raise ReadbackFailed(2U)
  }
  let kept_instance = instance.add_ref()
  let kept_device = device.add_ref()
  let kept_queue = queue.add_ref()
  let kept_command = command.add_ref()
  let kept_buffer = buffer.add_ref()
  let future = queue.submit_one_and_map_read_async(
    command, buffer, offset, size,
  )
  if future == 0UL {
    kept_buffer.release()
    kept_command.release()
    kept_queue.release()
    kept_device.release()
    kept_instance.release()
    raise ReadbackFailed(3U)
  }
  let ticket : ReadbackTicket = {
    id,
    poll: () => {
      kept_instance.process_events()
      ignore(kept_device.poll())
      kept_queue.map_read_async_status_u32(future)
    },
    read: () => kept_queue.map_read_async_read(future),
    cancel: () => kept_buffer.destroy(),
    clear: () => {
      kept_queue.map_read_async_clear(future)
      kept_buffer.release()
      kept_command.release()
      kept_queue.release()
      kept_device.release()
      kept_instance.release()
    },
  }
  let bytes = run_readback(
    ticket,
    registry,
    timeout_ms~,
    cleanup_ms~,
    poll_limit~,
  )
  if bytes.length().to_uint64() != size {
    raise ReadbackFailed(4U)
  }
  bytes
}
