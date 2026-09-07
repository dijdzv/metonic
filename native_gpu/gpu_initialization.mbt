///|
fn adapter_options(
  force_fallback : Bool,
  compatible_surface : @wgpu.Surface?,
  power_preference? : UInt = @wgpu.POWER_PREFERENCE_UNDEFINED,
) -> @c.WGPURequestAdapterOptionsPtr {
  let raw_surface = match compatible_surface {
    Some(surface) => surface.raw_handle()
    None => @c.null_surface()
  }
  @c.request_adapter_options_new_u32(
    @wgpu.FEATURE_LEVEL_CORE,
    power_preference,
    force_fallback,
    @wgpu.BACKEND_TYPE_D3_D12,
    raw_surface,
  )
}

///|
async fn initialize_adapter(
  owner : Initialization,
  instance : @wgpu.Instance,
  force_fallback : Bool,
  compatible_surface? : @wgpu.Surface? = None,
  power_preference? : UInt = @wgpu.POWER_PREFERENCE_UNDEFINED,
  poll_limit? : Int = 100000,
) -> @wgpu.Adapter raise Error {
  let id = owner.next_id
  owner.next_id += 1
  let kept_instance = instance.add_ref()
  let kept_surface = match compatible_surface {
    Some(surface) => Some(surface.add_ref())
    None => None
  }
  let options = adapter_options(force_fallback, kept_surface, power_preference~)
  let future = instance.request_adapter_future_id_u64(options~)
  @c.request_adapter_options_free(options)
  if future == 0UL {
    match kept_surface {
      Some(surface) => surface.release()
      None => ()
    }
    kept_instance.release()
    raise InitializationFailed::InitializationFailed(0U)
  }
  let result : Ref[@wgpu.Adapter?] = @ref.new(None)
  let ticket : InitTicket = {
    id,
    poll: () => {
      kept_instance.process_events()
      kept_instance.request_adapter_async_status_u32(future)
    },
    take: () => {
      let adapter = kept_instance.request_adapter_async_adapter(future)
      if @c.adapter_is_null(adapter.raw_handle()) {
        raise InitializationFailed::InitializationFailed(1U)
      }
      result.val = Some(adapter)
    },
    discard: () => {
      match result.val {
        Some(adapter) => {
          adapter.release()
          result.val = None
        }
        None => {
          let adapter = kept_instance.request_adapter_async_adapter(future)
          if !@c.adapter_is_null(adapter.raw_handle()) {
            adapter.release()
          }
        }
      }
    },
    clear: () => {
      kept_instance.request_adapter_async_clear(future)
      match kept_surface {
        Some(surface) => surface.release()
        None => ()
      }
      kept_instance.release()
    },
  }
  run_initialization(ticket, owner, poll_limit~)
  match result.val {
    Some(adapter) => adapter
    None => raise InitializationFailed::InitializationFailed(1U)
  }
}

///|
async fn initialize_device(
  owner : Initialization,
  instance : @wgpu.Instance,
  adapter : @wgpu.Adapter,
  poll_limit? : Int = 100000,
) -> @wgpu.Device raise Error {
  let id = owner.next_id
  owner.next_id += 1
  let kept_instance = instance.add_ref()
  let kept_adapter = adapter.add_ref()
  let future = adapter.request_device_future_id_u64()
  if future == 0UL {
    kept_adapter.release()
    kept_instance.release()
    raise InitializationFailed::InitializationFailed(0U)
  }
  let result : Ref[@wgpu.Device?] = @ref.new(None)
  let ticket : InitTicket = {
    id,
    poll: () => {
      kept_instance.process_events()
      kept_adapter.request_device_async_status_u32(future)
    },
    take: () => {
      let device = kept_adapter.request_device_async_device(future)
      if @c.device_is_null(device.raw_handle()) {
        raise InitializationFailed::InitializationFailed(1U)
      }
      result.val = Some(device)
    },
    discard: () => {
      match result.val {
        Some(device) => {
          device.release()
          result.val = None
        }
        None => {
          let device = kept_adapter.request_device_async_device(future)
          if !@c.device_is_null(device.raw_handle()) {
            device.release()
          }
        }
      }
    },
    clear: () => {
      kept_adapter.request_device_async_clear(future)
      kept_adapter.release()
      kept_instance.release()
    },
  }
  run_initialization(ticket, owner, poll_limit~)
  match result.val {
    Some(device) => device
    None => raise InitializationFailed::InitializationFailed(1U)
  }
}
