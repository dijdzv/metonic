import { createLayerRenderer } from './layer-renderer.mjs';
import { transfer_font_words } from './browser-buffer.mjs';

async function loadFont(app, disposed) {
  const bytes = new Uint8Array(await app.font_fetch());
  if (disposed()) return false;
  if (typeof app.font_receive === 'function') {
    if (app.font_receive(bytes.slice()) !== 1) throw new Error('MoonBit font_receive rejected font');
    return true;
  }
  if (app.font_begin(bytes.length) !== 1) throw new Error('MoonBit font_begin rejected font');
  if (!transfer_font_words(bytes, app.font_put)) throw new Error('MoonBit font_put rejected font');
  if (disposed()) return false;
  if (app.font_commit() !== 1) throw new Error('MoonBit font_commit rejected font');
  return true;
}

export async function createTextRenderer({ app, device, format, disposed }) {
  const loaded = await loadFont(app, disposed);
  if (!loaded || disposed()) return null;
  if (app.text_gpu_init(device, format) !== 1) throw new Error('MoonBit GPU initialization rejected format');
  const renderer = createLayerRenderer({
    raster: width => app.editor_render(width),
    width: () => app.text_width(),
    layerCount: () => app.view_layer_count(),
    layerField: (index, field) => app.view_layer_field(index, field),
    layerBytes: index => app.view_layer_bytes(index),
    beginUpload: () => app.text_gpu_abort(),
    upload: (index, pixels) => app.text_gpu_add(index, pixels),
    commitUpload: () => app.text_gpu_commit(),
    record: (index, uniform) => app.gpu_frame_text(index, uniform),
    dispose: () => { app.text_gpu_dispose(); app.text_dispose(); },
  });
  return { rasterText: renderer.refresh, record: renderer.record, stats: renderer.stats, dispose: renderer.dispose };
}