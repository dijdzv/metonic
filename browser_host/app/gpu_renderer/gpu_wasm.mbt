///|
#external
pub type GpuInitPromise

///|
fn gpu_resolve(value : Int) -> GpuInitPromise = "websys" "gpu_resolve"

///|
fn gpu_then_raw(
  promise : @js_async.Promise[@input_dom.GPURenderPipeline],
  callback : (@input_dom.GPURenderPipeline) -> Int,
) -> GpuInitPromise = "websys" "gpu_then"

///|
fn gpu_pipeline_then(
  promise : @input_dom.WebsysPromise[@input_dom.GPURenderPipeline],
  callback : (@input_dom.GPURenderPipeline) -> Int,
) -> GpuInitPromise {
  gpu_then_raw(promise.raw, callback)
}

///|
fn gpu_shader(
  device : @input_dom.GPUDevice,
  code : String,
) -> @input_dom.GPUShaderModule {
  device.create_shader_module({ code, })
}

///|
fn gpu_pipeline_descriptor(
  shader : @input_dom.GPUShaderModule,
  format : @input_dom.GPUTextureFormat,
) -> @input_dom.GPURenderPipelineDescriptor {
  {
    layout: Case1(Auto),
    vertex: { module_: shader, entryPoint: Some("vs"), },
    fragment: Some({
      module_: shader,
      entryPoint: Some("fs"),
      targets: [Some({ format, })],
    }),
  }
}

///|
fn gpu_uniform(device : @input_dom.GPUDevice) -> @input_dom.GPUBuffer {
  device.create_buffer({ size: 32UL, usage: 72U, mappedAtCreation: None, })
}

///|
fn gpu_group(
  device : @input_dom.GPUDevice,
  pipeline : @input_dom.GPURenderPipeline,
  uniform : @input_dom.GPUBuffer,
  texture : @input_dom.GPUTexture?,
) -> @input_dom.GPUBindGroup {
  let buffer : @input_dom.GPUBindGroupEntry = {
    binding: 0U,
    resource: Case4({ buffer: uniform, offset: None, size: None, }),
  }
  let entries = match texture {
    None => [buffer]
    Some(texture) =>
      [buffer, { binding: 1U, resource: Case2(texture.create_view()), }]
  }
  device.create_bind_group({
    layout: pipeline.get_bind_group_layout(0U),
    entries,
  })
}

///|
fn gpu_texture(
  device : @input_dom.GPUDevice,
  width : Int,
  height : Int,
) -> @input_dom.GPUTexture {
  device.create_texture({
    size: Case0([width.reinterpret_as_uint(), height.reinterpret_as_uint(), 1U]),
    format: Rgba8unorm,
    usage: 6U,
  })
}

///|
fn gpu_upload_texture(
  device : @input_dom.GPUDevice,
  texture : @input_dom.GPUTexture,
  pixels : @input_dom.ArrayBufferView,
  width : Int,
  height : Int,
) -> Unit {
  device
  .queue()
  .write_texture(
    { texture, },
    Case2(pixels),
    {
      offset: None,
      bytesPerRow: Some((width * 4).reinterpret_as_uint()),
      rowsPerImage: None,
    },
    Case0([width.reinterpret_as_uint(), height.reinterpret_as_uint(), 1U]),
  )
}

///|
fn gpu_record(
  device : @input_dom.GPUDevice,
  uniform : @input_dom.GPUBuffer,
  data : @input_dom.ArrayBufferView,
  pass : @input_dom.GPURenderPassEncoder,
  pipeline : @input_dom.GPURenderPipeline,
  group : @input_dom.GPUBindGroup,
) -> Unit {
  device.queue().write_buffer(uniform, 0UL, Case2(data))
  pass.set_pipeline(pipeline)
  pass.set_bind_group(0U, Some(group))
  pass.draw(6U)
}

///|
fn gpu_begin_pass(
  context : @input_dom.GPUCanvasContext,
  encoder : @input_dom.GPUCommandEncoder,
) -> @input_dom.GPURenderPassEncoder {
  let view = context.get_current_texture().create_view()
  encoder.begin_render_pass({
    colorAttachments: [
      Some({
        view,
        loadOp: Clear,
        storeOp: Store,
        clearValue: Some(Case1({ r: 0.02, g: 0.08, b: 0.15, a: 1.0, })),
      }),
    ],
  })
}

///|
fn gpu_submit(
  device : @input_dom.GPUDevice,
  command : @input_dom.GPUCommandBuffer,
) -> Unit {
  device.queue().submit([command])
}
