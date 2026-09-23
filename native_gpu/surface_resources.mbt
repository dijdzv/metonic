///|
/// App-owned texture counts and RGBA8 descriptor payload estimates.
/// WhyNot: swapchain textures and driver allocations are not owned by this
/// renderer, so these bytes are not physical GPU memory use.
pub(all) struct SurfaceGpuResources {
  text_texture_count : Int
  text_texture_bytes : UInt64
  peak_text_texture_count : Int
  peak_text_texture_bytes : UInt64
  retained_frame_count : Int
  retained_frame_bytes : UInt64
  uniform_buffer_bytes : UInt64
  closed : Bool
} derive(Eq, Debug)

///|
fn text_layer_bytes(width : Int, height : Int) -> UInt64 {
  width.to_uint64() * height.to_uint64() * 4UL
}

///|
fn replacement_footprint(
  old_count : Int,
  old_bytes : UInt64,
  next_count : Int,
  next_bytes : UInt64,
) -> (Int, UInt64) {
  (old_count + next_count, old_bytes + next_bytes)
}

///|
fn text_texture_bytes(layers : Array[SurfaceText]) -> UInt64 {
  let mut bytes = 0UL
  for layer in layers {
    bytes += layer.texture_bytes
  }
  bytes
}

///|
pub fn SurfaceRenderer::gpu_resources(
  self : SurfaceRenderer,
) -> SurfaceGpuResources {
  let (retained_count, retained_bytes) = self.retention.resource_footprint()
  {
    text_texture_count: self.text_layers.length(),
    text_texture_bytes: text_texture_bytes(self.text_layers),
    peak_text_texture_count: self.peak_text_texture_count,
    peak_text_texture_bytes: self.peak_text_texture_bytes,
    retained_frame_count: retained_count,
    retained_frame_bytes: retained_bytes,
    uniform_buffer_bytes: if self.closed {
      0UL
    } else {
      32UL
    },
    closed: self.closed,
  }
}
