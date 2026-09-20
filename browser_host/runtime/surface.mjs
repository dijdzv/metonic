export function createSurface({ canvas, onError, onFrame, onResize }) {
  let device, context, format, observer, raf = 0, disposed = false, started = false;
  let size;
  const fail = error => { if (!disposed) onError(error?.message || String(error)); };
  const onGpuError = event => fail(`GPU error: ${event.error.message}`);
  function schedule() {
    if (disposed || raf || !device) return;
    raf = requestAnimationFrame(() => {
      raf = 0;
      if (!disposed) {
        try { onFrame(); } catch (error) { fail(error); }
      }
    });
  }
  function resize(force = false) {
    if (disposed || !context) return;
    try {
      const rect = canvas.getBoundingClientRect();
      const width = Math.max(1, Math.round(rect.width));
      const height = Math.max(1, Math.round(rect.height));
      const dpr = Math.max(1, window.devicePixelRatio || 1);
      const max = device.limits.maxTextureDimension2D;
      const backingWidth = Math.min(max, Math.max(1, Math.round(width * dpr)));
      const backingHeight = Math.min(max, Math.max(1, Math.round(height * dpr)));
      if (!force && size && size.width === width && size.height === height
        && size.backingWidth === backingWidth && size.backingHeight === backingHeight) return;
      size = { width, height, backingWidth, backingHeight };
      canvas.width = backingWidth;
      canvas.height = backingHeight;
      context.configure({ device, format, alphaMode: 'opaque' });
      onResize(size);
    } catch (error) { fail(error); }
  }
  const resized = () => resize();
  return {
    async start() {
      if (started || disposed) throw new Error('Surface can only start once.');
      started = true;
      if (!window.isSecureContext) throw new Error('WebGPU requires a secure context (HTTPS or localhost).');
      if (!navigator.gpu) throw new Error('WebGPU is unavailable in this browser.');
      const adapter = await navigator.gpu.requestAdapter();
      if (disposed) return null;
      if (!adapter) throw new Error('WebGPU requestAdapter returned no adapter.');
      const nextDevice = await adapter.requestDevice();
      if (disposed) { nextDevice.destroy(); return null; }
      device = nextDevice;
      device.lost.then(info => fail(`GPU device lost: ${info.message || info.reason}`));
      device.addEventListener('uncapturederror', onGpuError);
      context = canvas.getContext('webgpu');
      if (!context) throw new Error('Could not acquire a WebGPU canvas context.');
      format = navigator.gpu.getPreferredCanvasFormat();
      return { adapter, device, context, format };
    },
    observe() {
      if (disposed || observer || !device) return;
      observer = new ResizeObserver(resized);
      observer.observe(canvas);
      window.addEventListener('resize', resized);
    },
    resize,
    schedule,
    dispose() {
      if (disposed) return;
      disposed = true;
      if (raf) cancelAnimationFrame(raf);
      raf = 0;
      observer?.disconnect();
      observer = undefined;
      window.removeEventListener('resize', resized);
      device?.removeEventListener('uncapturederror', onGpuError);
      try { context?.unconfigure(); } catch {}
      try { device?.destroy(); } catch {}
    },
  };
}
