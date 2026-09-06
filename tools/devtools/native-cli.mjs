import readline from 'node:readline';
import { createNativeSession, encodeCapture } from './native-session.mjs';

const MAX_LINE_BYTES = 4095;
let session;
let closing;
let input;

async function close() {
  if (!closing) closing = session?.close().catch((error) => { process.stderr.write(`${error.message}\n`); });
  await closing;
}

async function main() {
  session = await createNativeSession();
  input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  try {
    for await (const line of input) {
      if (Buffer.byteLength(line, 'utf8') > MAX_LINE_BYTES) {
        process.stdout.write(`${JSON.stringify({ ok: false, error: 'input line exceeds 4095 bytes' })}\n`);
        continue;
      }
      try {
        const request = JSON.parse(line);
        const op = request?.op;
        if (op === 'capture') {
          const captured = await session.client.capture(request.args);
          const png = await encodeCapture(captured);
          const response = captured.response;
          process.stdout.write(`${JSON.stringify({ response, image: { mimeType: 'image/png', data: png.toString('base64') } })}\n`);
        } else {
          const response = await session.client.request(op, request?.args);
          process.stdout.write(`${JSON.stringify(response)}\n`);
        }
      } catch (error) {
        process.stdout.write(`${JSON.stringify({ ok: false, error: error?.message || String(error) })}\n`);
      }
    }
  } finally {
    input.close();
    await close();
  }
}

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.once(signal, async () => {
    input?.close();
    process.stdin.pause();
    await close();
    process.exitCode = signal === 'SIGINT' ? 130 : 143;
  });
}

main().catch(async (error) => {
  process.stderr.write(`${error?.stack || error}\n`);
  await close();
  process.exitCode = 1;
});
