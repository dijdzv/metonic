import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../.work/browser-dist');
const files = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/index.html', ['index.html', 'text/html; charset=utf-8']],
  ['/style.css', ['style.css', 'text/css; charset=utf-8']],
  ['/host.mjs', ['host.mjs', 'text/javascript; charset=utf-8']],
  ['/loader.mjs', ['loader.mjs', 'text/javascript; charset=utf-8']],
  ['/text-renderer.mjs', ['text-renderer.mjs', 'text/javascript; charset=utf-8']],
  ['/app.mjs', ['app.mjs', 'text/javascript; charset=utf-8']],
  ['/app.wasm', ['app.wasm', 'application/wasm']],
  ['/NotoSansJP.ttf', ['NotoSansJP.ttf', 'font/ttf']],
  ['/OFL.txt', ['OFL.txt', 'text/plain; charset=utf-8']],
]);

const server = http.createServer((req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { Allow: 'GET, HEAD', 'Cache-Control': 'no-store' });
    res.end();
    return;
  }
  let pathname;
  try {
    pathname = new URL(req.url ?? '/', 'http://127.0.0.1').pathname;
  } catch {
    res.writeHead(400, { 'Cache-Control': 'no-store' });
    res.end();
    return;
  }
  const entry = files.get(pathname);
  if (!entry) {
    res.writeHead(404, { 'Cache-Control': 'no-store' });
    res.end();
    return;
  }
  const [name, type] = entry;
  const file = path.join(root, name);
  fs.stat(file, (statError, info) => {
    if (statError || !info.isFile()) {
      res.writeHead(404, { 'Cache-Control': 'no-store' });
      res.end();
      return;
    }
    res.writeHead(200, {
      'Content-Type': type,
      'Content-Length': info.size,
      'Cache-Control': 'no-store',
    });
    if (req.method === 'HEAD') res.end();
    else fs.createReadStream(file).on('error', (error) => {
      console.error(error);
      if (!res.headersSent) res.writeHead(500, { 'Cache-Control': 'no-store' });
      res.end();
    }).pipe(res);
  });
});

server.on('error', (error) => {
  console.error(error);
  process.exitCode = 1;
});
server.listen(4173, '127.0.0.1', () => {
  process.stdout.write('http://127.0.0.1:4173/\n');
});
