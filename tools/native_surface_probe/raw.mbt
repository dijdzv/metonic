///|
async fn raw_stage(name : String) -> Unit {
  @stdio.stderr.write("RAW_SURFACE_STAGE=" + name + "\n") catch {
    _ => ()
  }
}

///|
async fn raw_draw(
  surface : @wgpu.Surface,
  adapter : @wgpu.Adapter,
  device : @wgpu.Device,
  queue : @wgpu.Queue,
) -> Unit raise Error {
  raw_stage("draw-configure-before")
  let format = surface.configure_default(
    adapter,
    device,
    640U,
    360U,
    @wgpu.TextureUsage::from_u64(@wgpu.TEXTURE_USAGE_RENDER_ATTACHMENT),
  )
  if format.to_u32() == 0U {
    abort("raw surface configuration failed")
  }
  raw_stage("draw-configure-after")
  raw_stage("draw-acquire-before")
  let frame = surface.get_current_frame_or_raise()
  defer frame.release()
  raw_stage("draw-acquire-after")
  let view = frame.texture.create_view()
  defer view.release()
  let encoder = device.create_command_encoder()
  defer encoder.release()
  let pass = encoder.begin_render_pass_color_clear(view, 0.02, 0.08, 0.15, 1.0)
  pass.end()
  defer pass.release()
  let command = encoder.finish()
  defer command.release()
  queue.submit_one(command)
  raw_stage("draw-submit-after")
  raw_stage("draw-present-before")
  let present_error : Ref[@wgpu.SurfacePresentError?] = { val: None, }
  frame.present_or_raise() catch {
    error => {
      raw_stage("draw-present-error=" + error.message())
      present_error.val = Some(error)
    }
  }
  match present_error.val {
    Some(error) => raise error
    None => ()
  }
  raw_stage("draw-present-after")
}

///|
async fn raw_probe() -> Unit raise Error {
  raw_stage("create")
  let instance = @wgpu.Instance::create()
  defer instance.release()
  let mut surface = instance.create_surface_windows_hwnd(
    metonic_binding_hinstance(),
    metonic_binding_hwnd(),
  )
  let fresh = @env.get_env_var("METONIC_SURFACE_FRESH") == Some("1")
  raw_stage("generation1")
  let adapter = instance.request_adapter_sync_options_surface_u32(
    surface,
    power_preference_u32=@wgpu.POWER_PREFERENCE_HIGH_PERFORMANCE,
    force_fallback_adapter=@env.get_env_var("METONIC_GPU_FALLBACK") == Some("1"),
    backend_type_u32=@wgpu.BACKEND_TYPE_D3_D12,
  )
  let device = adapter.request_device_sync(instance)
  let queue = device.queue()
  raw_draw(surface, adapter, device, queue)
  surface.unconfigure()
  queue.release()
  device.release()
  adapter.release()
  if fresh {
    surface.release()
    surface = instance.create_surface_windows_hwnd(
      metonic_binding_hinstance(),
      metonic_binding_hwnd(),
    )
  }
  raw_stage("generation2")
  let adapter2 = instance.request_adapter_sync_options_surface_u32(
    surface,
    power_preference_u32=@wgpu.POWER_PREFERENCE_HIGH_PERFORMANCE,
    force_fallback_adapter=@env.get_env_var("METONIC_GPU_FALLBACK") == Some("1"),
    backend_type_u32=@wgpu.BACKEND_TYPE_D3_D12,
  )
  let device2 = adapter2.request_device_sync(instance)
  let queue2 = device2.queue()
  raw_draw(surface, adapter2, device2, queue2)
  surface.unconfigure()
  queue2.release()
  device2.release()
  adapter2.release()
  surface.release()
  raw_stage("done")
  println("RAW_SURFACE_OK")
  println("SURFACE_RENDERER_OK")
}
