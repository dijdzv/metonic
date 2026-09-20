import { unpack } from './browser-buffer.mjs';

export function createLayerRenderer({ raster, width, layerCount, layerField, layerBytes,
  beginUpload, upload, commitUpload, record, dispose }) {
  let layers = [], uploaded = 0, renders = 0, stopped = false;
  return {
    refresh(cssWidth) {
      if (stopped) throw new Error('Renderer is disposed');
      const result = raster(Math.trunc(cssWidth));
      if (result === 2) return;
      if (result !== 1) throw new Error('MoonBit rasterization rejected input');
      const next = [];
      beginUpload();
      try {
        for (let index = 0; index < layerCount(); index++) {
          const x = layerField(index, 0), y = layerField(index, 1);
          const width = layerField(index, 2), height = layerField(index, 3);
          const transferred = layerBytes(index);
          const pixels = transferred instanceof Uint8Array ? transferred.slice()
            : typeof transferred === 'string' ? unpack(transferred) : null;
          if (!pixels) throw new Error('MoonBit returned an unsupported pixel buffer');
          if (pixels.byteLength !== width * height * 4) throw new Error('MoonBit pixel buffer size mismatch');
          if (upload(index, pixels) !== 1) throw new Error('MoonBit GPU layer rejected upload');
          next.push({ x, y, width, height });
          uploaded += pixels.byteLength;
        }
        if (commitUpload() !== 1) throw new Error('MoonBit GPU batch rejected commit');
      } catch (error) { beginUpload(); throw error; }
      layers = next;
      renders++;
    },
    record(cssWidth, cssHeight) {
      if (stopped) throw new Error('Renderer is disposed');
      for (const [index, layer] of layers.entries()) {
        const uniform = new Float32Array([cssWidth, cssHeight, layer.x, layer.y, layer.width, layer.height, 0, 0]);
        if (record(index, uniform) !== 1) throw new Error('MoonBit GPU layer rejected draw');
      }
    },
    stats: () => ({ width: width(), renders, uploaded }),
    dispose() {
      if (stopped) return;
      stopped = true;
      dispose();
      layers = [];
    },
  };
}
