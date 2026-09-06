///|
struct Case {
  width : UInt
  height : UInt
  x : UInt
  y : UInt
  rw : UInt
  rh : UInt
  active : UInt
}

///|
fn uniform_bytes(words : Array[UInt]) -> Bytes {
  Bytes::makei(32, i => {
    ((words[i / 4] >> (i % 4 * 8)) & 0xFFU).reinterpret_as_int().to_byte()
  })
}

///|
fn expected_pixel(case_ : Case, x : UInt, y : UInt) -> Array[Int] {
  let inside = x >= case_.x &&
    x < case_.x + case_.rw &&
    y >= case_.y &&
    y < case_.y + case_.rh
  if !inside {
    [5, 20, 38, 255]
  } else if case_.active == 1U {
    [242, 97, 26, 255]
  } else {
    [20, 166, 173, 255]
  }
}

///|
test "wgpu rectangle rgba8 readback" {
  let instance = @wgpu.Instance::create()
  defer instance.release()
  let adapter = instance.request_adapter_sync_options_u32(
    backend_type_u32=@wgpu.BACKEND_TYPE_D3_D12,
    force_fallback_adapter=@env.get_env_var("METONIC_GPU_FALLBACK") == Some("1"),
  )
  defer adapter.release()
  assert_eq(adapter.info_backend_type_u32(), @wgpu.BACKEND_TYPE_D3_D12)
  let device = adapter.request_device_sync(instance)
  defer device.release()
  let queue = device.queue()
  defer queue.release()
  let layout = device.create_bind_group_layout_uniform_buffer()
  defer layout.release()
  let uniform = device.create_buffer(
    size=32UL,
    usage=@wgpu.BufferUsage::from_u64(
      @wgpu.BUFFER_USAGE_UNIFORM | @wgpu.BUFFER_USAGE_COPY_DST,
    ),
  )
  defer uniform.release()
  let bind_group = device.create_bind_group_uniform_buffer(layout, uniform)
  defer bind_group.release()
  let pipeline_layout = device.create_pipeline_layout_1(layout)
  defer pipeline_layout.release()
  let wgsl : String =
    #|struct Rect { rect: vec4<u32>, flags: vec4<u32> };
    #|@group(0) @binding(0) var<uniform> u: Rect;
    #|@vertex fn vs_main(@builtin(vertex_index) i: u32) -> @builtin(position) vec4<f32> {
    #|  var p = array<vec2<f32>, 3>(vec2<f32>(-1.0,-1.0), vec2<f32>(3.0,-1.0), vec2<f32>(-1.0,3.0));
    #|  return vec4<f32>(p[i], 0.0, 1.0);
    #|}
    #|@fragment fn fs_main(@builtin(position) p: vec4<f32>) -> @location(0) vec4<f32> {
    #|  let x = u32(p.x); let y = u32(p.y);
    #|  let inside = x >= u.rect.x && x < u.rect.x + u.rect.z && y >= u.rect.y && y < u.rect.y + u.rect.w;
    #|  if (!inside) { return vec4<f32>(0.02,0.08,0.15,1.0); }
    #|  if (u.flags.x == 1u) { return vec4<f32>(0.95,0.38,0.10,1.0); }
    #|  return vec4<f32>(0.08,0.65,0.68,1.0);
    #|}
  let shader = device.create_shader_module_wgsl(wgsl)
  defer shader.release()
  let pipeline = device.create_render_pipeline_rgba8_with_layout(
    pipeline_layout, shader,
  )
  defer pipeline.release()
  let cases = [
    {
      width: 640U,
      height: 360U,
      x: 260U,
      y: 144U,
      rw: 120U,
      rh: 72U,
      active: 0U,
    },
    {
      width: 640U,
      height: 360U,
      x: 10U,
      y: 20U,
      rw: 120U,
      rh: 72U,
      active: 1U,
    },
    {
      width: 317U,
      height: 193U,
      x: 197U,
      y: 121U,
      rw: 120U,
      rh: 72U,
      active: 1U,
    },
    { width: 1U, height: 1U, x: 0U, y: 0U, rw: 1U, rh: 1U, active: 0U, },
  ]
  let mut checks = 0
  for case_ in cases {
    let texture = device.create_texture_rgba8_2d(case_.width, case_.height)
    defer texture.release()
    let view = texture.create_view()
    defer view.release()
    queue.write_buffer(
      uniform,
      0UL,
      uniform_bytes([
        case_.x,
        case_.y,
        case_.rw,
        case_.rh,
        case_.active,
        0U,
        0U,
        0U,
      ]),
    )
    let encoder = device.create_command_encoder()
    defer encoder.release()
    let pass = encoder.begin_render_pass_color(view)
    pass.set_pipeline(pipeline)
    pass.set_bind_group(0U, bind_group, [])
    pass.draw(3U, 1U, 0U, 0U)
    pass.end()
    defer pass.release()
    let row = (case_.width * 4U + 255U) / 256U * 256U
    let size = row * case_.height
    let readback = device.create_buffer(
      size=size.to_uint64(),
      usage=@wgpu.BufferUsage::from_u64(
        @wgpu.BUFFER_USAGE_MAP_READ | @wgpu.BUFFER_USAGE_COPY_DST,
      ),
    )
    defer readback.release()
    encoder.copy_texture_to_buffer_rgba8(
      texture,
      readback,
      case_.width,
      case_.height,
    )
    let command = encoder.finish()
    defer command.release()
    queue.submit_one(command)
    let out = readback.readback(instance, 0UL, size.to_uint64())
    assert_eq(out.length(), size.reinterpret_as_int())
    let mut y = 0U
    while y < case_.height {
      let mut x = 0U
      while x < case_.width {
        let base = (y * row + x * 4U).reinterpret_as_int()
        let expected = expected_pixel(case_, x, y)
        let mut c = 0
        while c < 4 {
          assert_eq((out[base + c].to_int() - expected[c]).abs() <= 1, true)
          c += 1
        }
        x += 1U
      }
      y += 1U
    }
    checks += 1
  }
  println("adapter=" + adapter.info_device() + " checks=" + checks.to_string())
}
