const FONT_HASH = 'c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f';

async function loadFont(app, disposed) {
  const bytes = new Uint8Array(await app.font_fetch());
  if (disposed()) return false;
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  if (disposed()) return false;
  const hash = [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, '0')).join('');
  if (hash !== FONT_HASH) throw new Error('NotoSansJP.ttf SHA-256 mismatch');
  if (typeof app.font_receive === 'function') {
    if (app.font_receive(bytes.slice()) !== 1) throw new Error('MoonBit font_receive rejected font');
    return true;
  }
  if (app.font_begin(bytes.length) !== 1) throw new Error('MoonBit font_begin rejected font');
  for (let index = 0; index < bytes.length; index += 4) {
    let word = 0;
    for (let shift = 0; shift < 4 && index + shift < bytes.length; shift += 1) word |= bytes[index + shift] << (shift * 8);
    if (app.font_put(word) !== 1) throw new Error('MoonBit font_put rejected font');
  }
  if (disposed()) return false;
  if (app.font_commit() !== 1) throw new Error('MoonBit font_commit rejected font');
  return true;
}

export async function createTextRenderer({ app, device, format, disposed }) {
  const loaded = await loadFont(app, disposed);
  if (!loaded || disposed()) return null;
  if (app.text_gpu_init(device, format) !== 1) throw new Error('MoonBit GPU initialization rejected format');
  let layers = [];
  let uploaded = 0;
  let renders = 0;
  function rasterText(cssWidth) {
    const result = app.editor_render(Math.trunc(cssWidth));
    if (result === 2) return;
    if (result !== 1) throw new Error('MoonBit editor_render rejected input');
    const next = [];
    app.text_gpu_abort();
    try {
      for (let index = 0; index < app.view_layer_count(); index += 1) {
        const x = app.view_layer_field(index, 0), y = app.view_layer_field(index, 1);
        const width = app.view_layer_field(index, 2), height = app.view_layer_field(index, 3);
        const transferred = app.view_layer_bytes(index);
        let pixels;
        if (transferred instanceof Uint8Array) {
          pixels = transferred.slice();
        } else if (typeof transferred === 'string') {
          // This is a binary code-unit container; UTF-8 encoding would corrupt surrogate values.
          pixels = new Uint8Array(transferred.length * 2);
          for (let at = 0; at < transferred.length; at += 1) {
            const word = transferred.charCodeAt(at);
            pixels[at * 2] = word; pixels[at * 2 + 1] = word >>> 8;
          }
        } else {
          throw new Error('MoonBit returned an unsupported pixel buffer');
        }
        if (pixels.byteLength !== width * height * 4) throw new Error('MoonBit pixel buffer size mismatch');
        if (app.text_gpu_add(index, pixels) !== 1) throw new Error('MoonBit GPU layer rejected upload');
        const layer = { x, y, width, height };
        next.push(layer);
        uploaded += pixels.byteLength;
      }
      if (app.text_gpu_commit() !== 1) throw new Error('MoonBit GPU batch rejected commit');
    } catch (error) { app.text_gpu_abort(); throw error; }
    layers = next;
    renders += 1;
  }
  return {
    rasterText,
    record(pass, cssW, cssH) {
      for (const [index, layer] of layers.entries()) {
        if (app.text_gpu_record(pass, index, new Float32Array([cssW, cssH, layer.x, layer.y, layer.width, layer.height, 0, 0])) !== 1) throw new Error('MoonBit GPU layer rejected draw');
      }
    },
    stats: () => ({ width: app.text_width(), renders, uploaded }),
    dispose() { app.text_gpu_dispose(); layers = []; app.text_dispose(); },
  };
}
