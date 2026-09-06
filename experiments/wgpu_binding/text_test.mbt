///|
test "gpu text rgba readback" {
  let path = @env.get_env_var("METONIC_TEXT_RGBA").unwrap()
  let source = @fs.read_file_to_bytes(path)
  let expected_size = 640 * 96 * 4
  assert_eq(source.length(), expected_size)
  let mut has_white = false
  let mut has_non_white = false
  for i = 0; i < source.length(); i = i + 4 {
    let r = source[i].to_int()
    let g = source[i + 1].to_int()
    let b = source[i + 2].to_int()
    let a = source[i + 3].to_int()
    assert_eq(a, 255)
    if r == 255 && g == 255 && b == 255 {
      has_white = true
    } else {
      has_non_white = true
    }
  }
  assert_eq(has_white && has_non_white, true)
  let instance = @wgpu.Instance::create()
  defer instance.release()
  let fallback = @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1")
  let adapter = instance.request_adapter_sync_options_u32(
    backend_type_u32=@wgpu.BACKEND_TYPE_D3_D12,
    force_fallback_adapter=fallback,
  )
  defer adapter.release()
  assert_eq(adapter.info_backend_type_u32(), @wgpu.BACKEND_TYPE_D3_D12)
  let device = adapter.request_device_sync(instance)
  defer device.release()
  let queue = device.queue()
  defer queue.release()
  let texture = device.create_texture_rgba8_2d_with_usage(
    640U,
    96U,
    @wgpu.TextureUsage::from_u64(
      @wgpu.TEXTURE_USAGE_TEXTURE_BINDING | @wgpu.TEXTURE_USAGE_COPY_DST,
    ),
  )
  defer texture.release()
  queue.write_texture_rgba8_2d(texture, 640U, 96U, source)
  let sourceview = texture.create_view()
  defer sourceview.release()
  let wgsl : String =
    #|@group(0) @binding(0) var glyphs : texture_2d<f32>;
    #|@vertex fn vs_main(@builtin(vertex_index) i : u32) -> @builtin(position) vec4f {
    #|  let p = array<vec2f, 3>(vec2f(-1.0, -1.0), vec2f(3.0, -1.0), vec2f(-1.0, 3.0));
    #|  return vec4f(p[i], 0.0, 1.0);
    #|}
    #|@fragment fn fs_main(@builtin(position) p : vec4f) -> @location(0) vec4f {
    #|  return textureLoad(glyphs, vec2<i32>(p.xy), 0);
    #|}
  let shader = device.create_shader_module_wgsl(wgsl)
  defer shader.release()
  let pipeline = device.create_render_pipeline_rgba8(shader)
  defer pipeline.release()
  let layout = pipeline.get_bind_group_layout(0U)
  defer layout.release()
  let bindgroup = device.create_bind_group_texture_2d(layout, sourceview)
  defer bindgroup.release()
  let output = device.create_texture_rgba8_2d(640U, 96U)
  defer output.release()
  let outview = output.create_view()
  defer outview.release()
  let readback = device.create_buffer(
    size=245760UL,
    usage=@wgpu.BufferUsage::from_u64(
      @wgpu.BUFFER_USAGE_MAP_READ | @wgpu.BUFFER_USAGE_COPY_DST,
    ),
  )
  defer readback.release()
  let encoder = device.create_command_encoder()
  defer encoder.release()
  let pass = encoder.begin_render_pass_color(outview)
  defer pass.release()
  pass.set_pipeline(pipeline)
  pass.set_bind_group(0U, bindgroup, [])
  pass.draw(3U, 1U, 0U, 0U)
  pass.end()
  encoder.copy_texture_to_buffer_rgba8(output, readback, 640U, 96U)
  let command = encoder.finish()
  defer command.release()
  queue.submit_one(command)
  let result = readback.readback(instance, 0UL, 245760UL)
  assert_eq(result.length(), expected_size)
  for i = 0; i < expected_size; i = i + 1 {
    assert_eq((result[i].to_int() - source[i].to_int()).abs() <= 1, true)
  }
  println("GPU_TEXT_OK adapter=" + adapter.info_device() + " pixels=61440")
}
