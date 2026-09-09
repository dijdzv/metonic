const FONT_URL = './NotoSansJP.ttf';
const FONT_HASH = 'c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f';

async function loadFont(app, disposed) {
  const response = await fetch(FONT_URL, { cache: 'no-cache' });
  if (!response.ok) throw new Error(`Unable to fetch ${FONT_URL} (${response.status})`);
  const bytes = new Uint8Array(await response.arrayBuffer());
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
  const shader = device.createShaderModule({ code: `
struct U { viewport: vec2f, origin: vec2f, size: vec2f, tex: vec2f };
@group(0) @binding(0) var<uniform> u: U;
@group(0) @binding(1) var text_tex: texture_2d<f32>;
struct VertexOut { @builtin(position) position: vec4f, @location(0) uv: vec2f };
@vertex fn vs(@builtin(vertex_index) i:u32)->VertexOut { var p=array<vec2f,6>(vec2f(0,0),vec2f(1,0),vec2f(0,1),vec2f(0,1),vec2f(1,0),vec2f(1,1)); let q=u.origin+p[i]*u.size; var out:VertexOut; out.position=vec4f(q.x/u.viewport.x*2-1,1-q.y/u.viewport.y*2,0,1); out.uv=p[i]; return out; }
@fragment fn fs(in:VertexOut)->@location(0) vec4f { let dims=vec2i(textureDimensions(text_tex)); let pos=min(vec2i(in.uv*vec2f(dims)),dims-vec2i(1)); return textureLoad(text_tex,pos,0); }` });
  const pipeline = device.createRenderPipeline({ layout: 'auto', vertex: { module: shader, entryPoint: 'vs' }, fragment: { module: shader, entryPoint: 'fs', targets: [{ format }] }, primitive: { topology: 'triangle-list' } });
  let layers = [];
  let uploaded = 0;
  let renders = 0;
  function releaseLayers(values) { for (const layer of values) { layer.texture.destroy(); layer.uniform.destroy(); } }
  function rasterText(cssWidth) {
    const result = app.editor_render(Math.trunc(cssWidth));
    if (result === 2) return;
    if (result !== 1) throw new Error('MoonBit editor_render rejected input');
    const next = [];
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
        const texture = device.createTexture({ size: { width, height }, format: 'rgba8unorm', usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST });
        const uniform = device.createBuffer({ size: 32, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
        const layer = { x, y, width, height, texture, uniform };
        next.push(layer);
        device.queue.writeTexture({ texture }, pixels, { bytesPerRow: width * 4 }, { width, height });
        layer.bindGroup = device.createBindGroup({ layout: pipeline.getBindGroupLayout(0), entries: [{ binding: 0, resource: { buffer: uniform } }, { binding: 1, resource: texture.createView() }] });
        uploaded += pixels.byteLength;
      }
    } catch (error) { releaseLayers(next); throw error; }
    releaseLayers(layers);
    layers = next;
    renders += 1;
  }
  return {
    rasterText,
    record(pass, cssW, cssH) {
      pass.setPipeline(pipeline);
      for (const layer of layers) {
        device.queue.writeBuffer(layer.uniform, 0, new Float32Array([cssW, cssH, layer.x, layer.y, layer.width, layer.height, 0, 0]));
        pass.setBindGroup(0, layer.bindGroup); pass.draw(6);
      }
    },
    stats: () => ({ width: app.text_width(), renders, uploaded }),
    dispose() { releaseLayers(layers); layers = []; app.text_dispose(); },
  };
}
