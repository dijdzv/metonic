import readline from 'node:readline';

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
let revision = 0;
const state = { x: 260, y: 144, w: 120, h: 72, active: 0, viewportW: 640, viewportH: 360 };

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function response(id, extra = {}) {
  return { version: 1, id, ok: true, error: null, state: [state.x, state.y, state.w, state.h, state.active, revision, state.viewportW, state.viewportH], frame: 0, ...extra };
}

function snapshot() {
  return { ...state, revision };
}

rl.on('line', (line) => {
  let request;
  try { request = JSON.parse(line); } catch { send({ id: 'malformed-response', error: 'malformed request' }); return; }
  const id = request.id;
  const op = request.op;
  const args = request;
  if (op === 'shutdown') { send(response(id)); rl.close(); return; }
  if (op === 'delay') { setTimeout(() => send(response(id, { value: args.value ?? null })), Number(args.ms ?? 50)); return; }
  if (op === 'exit') { process.exit(Number(args.code ?? 17)); }
  if (op === 'stderrFlood') { process.stderr.write('x'.repeat(Number(args.bytes ?? 65536))); send(response(id)); return; }
  if (op === 'malformed') { process.stdout.write('{malformed json}\n'); return; }
  if (op === 'unknownID') { send(response(Number(id) + 123)); return; }
  if (op === 'oversize') { send({ id, value: 'x'.repeat(Number(args.bytes ?? 2 * 1024 * 1024)) }); return; }
  if (op === 'echo') { send(response(id, { value: args })); return; }
  if (op === 'snapshot') { send(response(id)); return; }
  if (op === 'resize') { state.viewportW = args.width; state.viewportH = args.height; revision += 1; send(response(id)); return; }
  send(response(id, { ok: false, error: `unknown operation: ${String(op)}` }));
});
