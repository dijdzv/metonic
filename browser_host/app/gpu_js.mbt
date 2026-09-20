///|
pub type GpuInitPromise

///|
extern "js" fn gpu_resolve(value : Int) -> GpuInitPromise =
  #| value => Promise.resolve(value)

///|
extern "js" fn gpu_pipeline_then(
  promise : @js_async.Promise[@input_dom.GPURenderPipeline],
  callback : (@input_dom.GPURenderPipeline) -> Int,
) -> GpuInitPromise =
  #| (promise, callback) => promise.then(callback)

///|
fn gpu_shader(
  device : @input_dom.GPUDevice,
  code : String,
) -> @input_dom.GPUShaderModule {
  device.create_shader_module(@input_dom.GPUShaderModuleDescriptor::{
    ..@input_dom.GPUShaderModuleDescriptor::default(),
    code,
  })
}

///|
fn gpu_pipeline_descriptor(
  shader : @input_dom.GPUShaderModule,
  format : @input_dom.GPUTextureFormat,
) -> @input_dom.GPURenderPipelineDescriptor {
  @input_dom.GPURenderPipelineDescriptor::{
    ..@input_dom.GPURenderPipelineDescriptor::new(
      layout=@input_dom.GPUPipelineLayoutOrGPUAutoLayoutMode::from_gpu_auto_layout_mode(
        Auto,
      ),
      vertex=@input_dom.GPUVertexState::{
        ..@input_dom.GPUVertexState::new(module_=shader),
        entryPoint: Some("vs"),
      },
    ),
    fragment: Some(@input_dom.GPUFragmentState::{
      ..@input_dom.GPUFragmentState::new(module_=shader),
      entryPoint: Some("fs"),
      targets: [@input_dom.GPUColorTargetState::new(format~).to_js()],
    }),
  }
}

///|
fn gpu_uniform(device : @input_dom.GPUDevice) -> @input_dom.GPUBuffer {
  device
  .create_buffer(@input_dom.GPUBufferDescriptor::new(size=32L, usage=72))
  .unwrap()
}

///|
fn gpu_group(
  device : @input_dom.GPUDevice,
  pipeline : @input_dom.GPURenderPipeline,
  uniform : @input_dom.GPUBuffer,
  texture : @input_dom.GPUTexture?,
) -> @input_dom.GPUBindGroup {
  let buffer = @input_dom.GPUBindGroupEntry::new(
    binding=0,
    resource=@input_dom.GPUBindingResource::from_gpu_buffer_binding(
      @input_dom.GPUBufferBinding::new(buffer=uniform),
    ),
  )
  let entries : FixedArray[@input_dom.GPUBindGroupEntry] = match texture {
    None => [buffer]
    Some(texture) =>
      [
        buffer,
        @input_dom.GPUBindGroupEntry::new(
          binding=1,
          resource=@input_dom.GPUBindingResource::from_gpu_texture_view(
            texture.create_view(),
          ),
        ),
      ]
  }
  device.create_bind_group(@input_dom.GPUBindGroupDescriptor::{
    ..@input_dom.GPUBindGroupDescriptor::new(
      layout=pipeline.get_bind_group_layout(0),
    ),
    entries,
  })
}

///|
fn gpu_texture(
  device : @input_dom.GPUDevice,
  width : Int,
  height : Int,
) -> @input_dom.GPUTexture {
  device.create_texture(
    @input_dom.GPUTextureDescriptor::new(
      size=@input_dom.GPUExtent3D::from_array_of_gpu_integer_coordinate([
        width, height, 1,
      ]),
      format=Rgba8unorm,
      usage=6,
    ),
  )
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
  .get_queue()
  .write_texture(
    @input_dom.GPUTexelCopyTextureInfo::new(texture~),
    @input_dom.AllowSharedBufferSource::from_array_buffer_view(pixels),
    @input_dom.GPUTexelCopyBufferLayout::{
      ..@input_dom.GPUTexelCopyBufferLayout::default(),
      bytesPerRow: Some(width * 4),
    },
    @input_dom.GPUExtent3D::from_array_of_gpu_integer_coordinate([
      width, height, 1,
    ]),
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
  device
  .get_queue()
  .write_buffer(
    uniform,
    0L,
    @input_dom.AllowSharedBufferSource::from_array_buffer_view(data),
  )
  .unwrap()
  pass.set_pipeline(pipeline)
  pass.set_bind_group(0, Some(group))
  pass.draw(6)
}

///|
fn gpu_begin_pass(
  context : @input_dom.GPUCanvasContext,
  encoder : @input_dom.GPUCommandEncoder,
) -> @input_dom.GPURenderPassEncoder {
  let view = context.get_current_texture().unwrap().create_view()
  let attachment = @input_dom.GPURenderPassColorAttachment::{
    ..@input_dom.GPURenderPassColorAttachment::new(
      view=@input_dom.GPUTextureOrGPUTextureView::from_gpu_texture_view(view),
      loadOp=Clear,
      storeOp=Store,
    ),
    clearValue: Some(
      @input_dom.GPUColor::from_gpu_color_dict(@input_dom.GPUColorDict::{
        r: 0.02,
        g: 0.08,
        b: 0.15,
        a: 1.0,
      }),
    ),
  }
  encoder.begin_render_pass(@input_dom.GPURenderPassDescriptor::{
    ..@input_dom.GPURenderPassDescriptor::default(),
    colorAttachments: [attachment.to_js()],
  })
}

///|
fn gpu_submit(
  device : @input_dom.GPUDevice,
  command : @input_dom.GPUCommandBuffer,
) -> Unit {
  device.get_queue().submit([command])
}
