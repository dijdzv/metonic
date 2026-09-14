///|
struct FrameRetention {}

///|
priv struct PendingFrame {}

///|
priv struct PresentationAttempt {}

///|
fn FrameRetention::begin_present(
  _self : FrameRetention,
  _surface : @wgpu.Surface,
) -> PresentationAttempt {
  PresentationAttempt::{ }
}

///|
fn FrameRetention::new(
  _surface : @wgpu.Surface,
  _adapter : @wgpu.Adapter,
) -> FrameRetention {
  FrameRetention::{ }
}

///|
fn FrameRetention::usage(_self : FrameRetention) -> @wgpu.TextureUsage {
  @wgpu.TextureUsage::from_u64(@wgpu.TEXTURE_USAGE_RENDER_ATTACHMENT)
}

///|
fn FrameRetention::reconfigured(_self : FrameRetention) -> Unit {
  ()
}

///|
fn FrameRetention::copy(
  _self : FrameRetention,
  _device : @wgpu.Device,
  _encoder : @wgpu.CommandEncoder,
  _texture : @wgpu.Texture,
  _width : UInt,
  _height : UInt,
  _format : @wgpu.TextureFormat,
  _display_scale : Double?,
) -> PendingFrame {
  PendingFrame::{ }
}

///|
fn FrameRetention::publish(
  _self : FrameRetention,
  _frame : PendingFrame,
  _attempt : PresentationAttempt,
  _surface : @wgpu.Surface,
) -> Unit {
  ()
}

///|
fn FrameRetention::close(_self : FrameRetention) -> Unit {
  ()
}

///|
fn PendingFrame::close(_self : PendingFrame) -> Unit {
  ()
}
