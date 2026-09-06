use std::ffi::c_void;
use std::num::NonZeroIsize;
use std::panic::{AssertUnwindSafe, catch_unwind};

use raw_window_handle::{
    RawDisplayHandle, RawWindowHandle, Win32WindowHandle, WindowsDisplayHandle,
};
use wgpu::util::DeviceExt;

#[repr(C)]
pub struct WindowContext {
    surface: wgpu::Surface<'static>,
    _instance: wgpu::Instance,
    device: wgpu::Device,
    queue: wgpu::Queue,
    pipeline: wgpu::RenderPipeline,
    uniforms: wgpu::Buffer,
    bind_group: wgpu::BindGroup,
    config: wgpu::SurfaceConfiguration,
}

fn with_result<T>(f: impl FnOnce() -> Result<T, String>) -> Result<T, String> {
    catch_unwind(AssertUnwindSafe(f)).map_err(|_| "native window bridge panicked".to_owned())?
}

fn create_inner(hwnd: *mut c_void, fallback: bool) -> Result<*mut WindowContext, String> {
    if hwnd.is_null() {
        return Err("null HWND".into());
    }
    let hwnd = NonZeroIsize::new(hwnd as isize).ok_or("invalid HWND")?;
    let window = RawWindowHandle::Win32(Win32WindowHandle::new(hwnd));
    let display = RawDisplayHandle::Windows(WindowsDisplayHandle::new());
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
        backends: wgpu::Backends::DX12,
        ..wgpu::InstanceDescriptor::new_without_display_handle()
    });
    let surface = unsafe {
        instance.create_surface_unsafe(wgpu::SurfaceTargetUnsafe::RawHandle {
            raw_display_handle: Some(display),
            raw_window_handle: window,
        })
    }
    .map_err(|e| e.to_string())?;
    let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        compatible_surface: Some(&surface),
        force_fallback_adapter: fallback,
        ..Default::default()
    }))
    .map_err(|e| e.to_string())?;
    eprintln!(
        "adapter: {} ({:?})",
        adapter.get_info().name,
        adapter.get_info().backend
    );
    let (device, queue) =
        pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor::default()))
            .map_err(|e| e.to_string())?;
    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("rectangle"),
        source: wgpu::ShaderSource::Wgsl(include_str!("rectangle.wgsl").into()),
    });
    let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("uniforms"),
        entries: &[wgpu::BindGroupLayoutEntry {
            binding: 0,
            visibility: wgpu::ShaderStages::VERTEX_FRAGMENT,
            ty: wgpu::BindingType::Buffer {
                ty: wgpu::BufferBindingType::Uniform,
                has_dynamic_offset: false,
                min_binding_size: None,
            },
            count: None,
        }],
    });
    let uniforms = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("rectangle uniforms"),
        contents: &[0; 32],
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
    });
    let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("uniforms"),
        layout: &layout,
        entries: &[wgpu::BindGroupEntry {
            binding: 0,
            resource: uniforms.as_entire_binding(),
        }],
    });
    let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("rectangle pipeline"),
        bind_group_layouts: &[Some(&layout)],
        immediate_size: 0,
    });
    let config = surface
        .get_default_config(&adapter, 640, 360)
        .ok_or("surface has no supported configuration")?;
    let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("rectangle"),
        layout: Some(&pipeline_layout),
        vertex: wgpu::VertexState {
            module: &shader,
            entry_point: Some("vs"),
            buffers: &[],
            compilation_options: Default::default(),
        },
        fragment: Some(wgpu::FragmentState {
            module: &shader,
            entry_point: Some("fs"),
            targets: &[Some(config.format.into())],
            compilation_options: Default::default(),
        }),
        primitive: Default::default(),
        depth_stencil: None,
        multisample: Default::default(),
        multiview_mask: None,
        cache: None,
    });
    surface.configure(&device, &config);
    Ok(Box::into_raw(Box::new(WindowContext {
        surface,
        _instance: instance,
        device,
        queue,
        pipeline,
        uniforms,
        bind_group,
        config,
    })))
}

#[unsafe(no_mangle)]
pub extern "C" fn metonic_surface_create(hwnd: *mut c_void, fallback: i32) -> *mut WindowContext {
    match with_result(|| create_inner(hwnd, fallback != 0)) {
        Ok(value) => value,
        Err(error) => {
            eprintln!("surface create: {error}");
            std::ptr::null_mut()
        }
    }
}

fn present_inner(
    ctx: &mut WindowContext,
    width: i32,
    height: i32,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    active: i32,
) -> Result<(), String> {
    if !(1..=2048).contains(&width)
        || !(1..=2048).contains(&height)
        || x < 0
        || y < 0
        || w < 1
        || h < 1
        || x > width
        || y > height
        || w > width - x
        || h > height - y
    {
        return Err("invalid surface dimensions or rectangle".into());
    }
    if ctx.config.width != width as u32 || ctx.config.height != height as u32 {
        ctx.config.width = width as u32;
        ctx.config.height = height as u32;
        ctx.surface.configure(&ctx.device, &ctx.config);
    }
    let values = [
        x as f32,
        y as f32,
        w as f32,
        h as f32,
        width as f32,
        height as f32,
        active as f32,
        0.0,
    ];
    let bytes = unsafe {
        std::slice::from_raw_parts(values.as_ptr() as *const u8, std::mem::size_of_val(&values))
    };
    ctx.queue.write_buffer(&ctx.uniforms, 0, bytes);
    let frame = match ctx.surface.get_current_texture() {
        wgpu::CurrentSurfaceTexture::Success(frame)
        | wgpu::CurrentSurfaceTexture::Suboptimal(frame) => frame,
        wgpu::CurrentSurfaceTexture::Lost | wgpu::CurrentSurfaceTexture::Outdated => {
            ctx.surface.configure(&ctx.device, &ctx.config);
            match ctx.surface.get_current_texture() {
                wgpu::CurrentSurfaceTexture::Success(frame)
                | wgpu::CurrentSurfaceTexture::Suboptimal(frame) => frame,
                other => return Err(format!("surface acquisition failed: {other:?}")),
            }
        }
        other => return Err(format!("surface acquisition failed: {other:?}")),
    };
    let view = frame
        .texture
        .create_view(&wgpu::TextureViewDescriptor::default());
    let mut encoder = ctx
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("present"),
        });
    {
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("rectangle pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &view,
                depth_slice: None,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color {
                        r: 0.02,
                        g: 0.08,
                        b: 0.15,
                        a: 1.0,
                    }),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            occlusion_query_set: None,
            timestamp_writes: None,
            multiview_mask: None,
        });
        pass.set_pipeline(&ctx.pipeline);
        pass.set_bind_group(0, &ctx.bind_group, &[]);
        pass.draw(0..6, 0..1);
    }
    ctx.queue.submit(Some(encoder.finish()));
    ctx.queue.present(frame);
    Ok(())
}

#[unsafe(no_mangle)]
pub extern "C" fn metonic_surface_present(
    ctx: *mut WindowContext,
    width: i32,
    height: i32,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    active: i32,
) -> i32 {
    if ctx.is_null() {
        return -1;
    }
    match with_result(|| present_inner(unsafe { &mut *ctx }, width, height, x, y, w, h, active)) {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("surface present: {error}");
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn metonic_surface_destroy(ctx: *mut WindowContext) {
    if ctx.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        drop(Box::from_raw(ctx));
    }));
}
