import { createServer } from 'node:http';
import { readFile, realpath } from 'node:fs/promises';
import path from 'node:path';

export async function serve(root) {
  root = await realpath(root);
  const server = createServer(async (req, res) => {
    try {
      const name = new URL(req.url, 'http://localhost').pathname.slice(1) || 'index.html';
      if (!/^[A-Za-z0-9_.-]+$/.test(name)) { res.writeHead(400).end(); return; }
      if (name === 'favicon.ico') { res.writeHead(204).end(); return; }
      const types = { '.html': 'text/html', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.ttf': 'font/ttf' };
      res.setHeader('content-type', types[path.extname(name)] || 'application/octet-stream');
      res.end(await readFile(path.join(root, name)));
    } catch { res.writeHead(404).end(); }
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  return {
    url: `http://127.0.0.1:${server.address().port}/`,
    close: () => new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve())),
  };
}
