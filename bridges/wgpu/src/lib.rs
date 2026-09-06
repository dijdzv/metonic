use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;
use std::sync::mpsc;
use std::time::Duration;

const MAX_DIMENSION: i32 = 2048;
const BACKGROUND: wgpu::Color = wgpu::Color {
    r: 0.02,
    g: 0.08,
    b: 0.15,
    a: 1.0,
};

/// Owns one DX12 adapter/device pair and is intended for single-threaded C API access.
pub struct Context {
    device: wgpu::Device,
    queue: wgpu::Queue,
    pipeline: wgpu::RenderPipeline,
    bind_group: wgpu::BindGroup,
    uniform: wgpu::Buffer,
    adapter_info: wgpu::AdapterInfo,
}

fn create_context(force_fallback: bool) -> Result<Box<Context>, String> {
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
        backends: wgpu::Backends::DX12,
        ..wgpu::InstanceDescriptor::new_without_display_handle()
    });
    let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        force_fallback_adapter: force_fallback,
        compatible_surface: None,
        ..Default::default()
    }))
    .map_err(|error| format!("request_adapter failed: {error}"))?;
    let adapter_info = adapter.get_info();
    let descriptor = wgpu::DeviceDescriptor {
        required_features: wgpu::Features::empty(),
        required_limits: wgpu::Limits::downlevel_defaults(),
        ..Default::default()
    };
    let (device, queue) = pollster::block_on(adapter.request_device(&descriptor))
        .map_err(|error| format!("request_device failed: {error}"))?;
    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("metonic rectangle shader"),
        source: wgpu::ShaderSource::Wgsl(include_str!("rectangle.wgsl").into()),
    });
    let uniform = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("metonic rectangle uniforms"),
        size: 32,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("metonic rectangle bind group layout"),
        entries: &[wgpu::BindGroupLayoutEntry {
            binding: 0,
            visibility: wgpu::ShaderStages::VERTEX_FRAGMENT,
            ty: wgpu::BindingType::Buffer {
                ty: wgpu::BufferBindingType::Uniform,
                has_dynamic_offset: false,
                min_binding_size: wgpu::BufferSize::new(32),
            },
            count: None,
        }],
    });
    let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("metonic rectangle bind group"),
        layout: &bind_group_layout,
        entries: &[wgpu::BindGroupEntry {
            binding: 0,
            resource: uniform.as_entire_binding(),
        }],
    });
    let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("metonic rectangle pipeline layout"),
        bind_group_layouts: &[Some(&bind_group_layout)],
        immediate_size: 0,
    });
    let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("metonic rectangle pipeline"),
        layout: Some(&pipeline_layout),
        vertex: wgpu::VertexState {
            module: &shader,
            entry_point: Some("vs"),
            compilation_options: Default::default(),
            buffers: &[],
        },
        fragment: Some(wgpu::FragmentState {
            module: &shader,
            entry_point: Some("fs"),
            compilation_options: Default::default(),
            targets: &[Some(wgpu::ColorTargetState {
                format: wgpu::TextureFormat::Rgba8Unorm,
                blend: None,
                write_mask: wgpu::ColorWrites::ALL,
            })],
        }),
        primitive: wgpu::PrimitiveState::default(),
        depth_stencil: None,
        multisample: wgpu::MultisampleState::default(),
        multiview_mask: None,
        cache: None,
    });
    Ok(Box::new(Context {
        device,
        queue,
        pipeline,
        bind_group,
        uniform,
        adapter_info,
    }))
}

fn render(
    context: &Context,
    width: i32,
    height: i32,
    x: i32,
    y: i32,
    rect_width: i32,
    rect_height: i32,
    active: i32,
    pixels: *mut u8,
    pixels_len: usize,
) -> Result<(), String> {
    if pixels.is_null()
        || width < 1
        || height < 1
        || width > MAX_DIMENSION
        || height > MAX_DIMENSION
    {
        return Err("invalid output dimensions or null pixels".into());
    }
    if x < 0
        || y < 0
        || rect_width < 1
        || rect_height < 1
        || x.checked_add(rect_width).is_none_or(|end| end > width)
        || y.checked_add(rect_height).is_none_or(|end| end > height)
    {
        return Err("rectangle is outside the output bounds".into());
    }
    let required = (width as usize)
        .checked_mul(height as usize)
        .and_then(|value| value.checked_mul(4))
        .ok_or_else(|| "output size overflow".to_string())?;
    if pixels_len < required {
        return Err("pixels buffer is too small".into());
    }
    let width_u32 = width as u32;
    let height_u32 = height as u32;
    let unpadded = width_u32 * 4;
    let padded = (unpadded + 255) & !255;
    let texture = context.device.create_texture(&wgpu::TextureDescriptor {
        label: Some("metonic rectangle output"),
        size: wgpu::Extent3d {
            width: width_u32,
            height: height_u32,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8Unorm,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    let readback = context.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("metonic rectangle readback"),
        size: padded as u64 * height_u32 as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut uniform_bytes = [0u8; 32];
    for (offset, value) in [x, y, rect_width, rect_height, width, height]
        .into_iter()
        .enumerate()
    {
        uniform_bytes[offset * 4..offset * 4 + 4].copy_from_slice(&(value as f32).to_le_bytes());
    }
    uniform_bytes[24..28].copy_from_slice(&(if active != 0 { 1.0f32 } else { 0.0 }).to_le_bytes());
    context
        .queue
        .write_buffer(&context.uniform, 0, &uniform_bytes);
    let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
    let mut encoder = context
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("metonic rectangle encoder"),
        });
    {
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("metonic rectangle pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &view,
                depth_slice: None,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(BACKGROUND),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            occlusion_query_set: None,
            timestamp_writes: None,
            multiview_mask: None,
        });
        pass.set_pipeline(&context.pipeline);
        pass.set_bind_group(0, &context.bind_group, &[]);
        pass.draw(0..6, 0..1);
    }
    encoder.copy_texture_to_buffer(
        wgpu::TexelCopyTextureInfo {
            texture: &texture,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::TexelCopyBufferInfo {
            buffer: &readback,
            layout: wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(padded),
                rows_per_image: Some(height_u32),
            },
        },
        wgpu::Extent3d {
            width: width_u32,
            height: height_u32,
            depth_or_array_layers: 1,
        },
    );
    let submission = context.queue.submit(Some(encoder.finish()));
    let slice = readback.slice(..);
    let (sender, receiver) = mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |result| {
        let _ = sender.send(result);
    });
    context
        .device
        .poll(wgpu::PollType::Wait {
            submission_index: Some(submission),
            timeout: Some(Duration::from_secs(10)),
        })
        .map_err(|error| format!("GPU poll failed: {error}"))?;
    receiver
        .recv_timeout(Duration::from_secs(10))
        .map_err(|error| format!("readback timed out: {error}"))?
        .map_err(|error| format!("readback mapping failed: {error}"))?;
    let mapped = slice
        .get_mapped_range()
        .map_err(|error| format!("mapped range failed: {error}"))?;
    unsafe {
        let destination = std::slice::from_raw_parts_mut(pixels, required);
        for row in 0..height as usize {
            let source_start = row * padded as usize;
            let destination_start = row * width as usize * 4;
            destination[destination_start..destination_start + width as usize * 4]
                .copy_from_slice(&mapped[source_start..source_start + width as usize * 4]);
        }
    }
    drop(mapped);
    readback.unmap();
    Ok(())
}

fn info_string(context: &Context) -> String {
    format!(
        "name={} backend={:?} device_type={:?}",
        context.adapter_info.name, context.adapter_info.backend, context.adapter_info.device_type
    )
}

/// Creates a DX12-backed context. Returns null on failure; diagnostics go to stderr.
#[unsafe(no_mangle)]
pub extern "C" fn metonic_gpu_create(force_fallback: i32) -> *mut Context {
    match catch_unwind(AssertUnwindSafe(|| create_context(force_fallback != 0))) {
        Ok(Ok(context)) => Box::into_raw(context),
        Ok(Err(error)) => {
            eprintln!("metonic_gpu_create: {error}");
            ptr::null_mut()
        }
        Err(_) => {
            eprintln!("metonic_gpu_create: panic");
            ptr::null_mut()
        }
    }
}

/// Renders and completes RGBA readback before returning. The context is single-threaded.
#[unsafe(no_mangle)]
pub extern "C" fn metonic_gpu_render(
    ctx: *mut Context,
    width: i32,
    height: i32,
    x: i32,
    y: i32,
    rect_width: i32,
    rect_height: i32,
    active: i32,
    pixels: *mut u8,
    pixels_len: usize,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if ctx.is_null() {
            return Err("null context".into());
        }
        unsafe {
            render(
                &*ctx,
                width,
                height,
                x,
                y,
                rect_width,
                rect_height,
                active,
                pixels,
                pixels_len,
            )
        }
    }));
    match result {
        Ok(Ok(())) => 0,
        Ok(Err(error)) => {
            eprintln!("metonic_gpu_render: {error}");
            -1
        }
        Err(_) => {
            eprintln!("metonic_gpu_render: panic");
            -1
        }
    }
}

/// Writes a null-terminated adapter description and returns its byte length, or -1.
#[unsafe(no_mangle)]
pub extern "C" fn metonic_gpu_info(ctx: *mut Context, output: *mut u8, capacity: usize) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<i32, String> {
        if ctx.is_null() || output.is_null() || capacity == 0 {
            return Err("invalid info buffer".into());
        }
        let bytes = info_string(unsafe { &*ctx }).into_bytes();
        if bytes.len() + 1 > capacity {
            return Err("info buffer is too small".into());
        }
        unsafe {
            ptr::copy_nonoverlapping(bytes.as_ptr(), output, bytes.len());
            *output.add(bytes.len()) = 0;
        }
        Ok(bytes.len() as i32)
    }));
    match result {
        Ok(Ok(length)) => length,
        Ok(Err(_)) | Err(_) => -1,
    }
}

/// Destroys a context. Null is accepted; double free of a non-null pointer is caller error.
#[unsafe(no_mangle)]
pub extern "C" fn metonic_gpu_destroy(ctx: *mut Context) {
    if ctx.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        drop(Box::from_raw(ctx));
    }));
}
