import { spawn } from 'node:child_process'
import { randomUUID } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const MAX_LINE = 64 * 1024
const MAX_JSON = 4095

export class NativeClient {
  constructor({ executable, bridge, capturePath, args = [], env = {}, timeoutMs = 15000, maxPending = 16 }) {
    if (!path.isAbsolute(executable) || !path.isAbsolute(bridge) || !path.isAbsolute(capturePath)) throw new TypeError('executable, bridge, and capturePath must be absolute paths')
    if (!Array.isArray(args) || !args.every((arg) => typeof arg === 'string')) throw new TypeError('args must be an array of strings')
    if (!Number.isFinite(timeoutMs) || timeoutMs <= 0 || !Number.isInteger(maxPending) || maxPending <= 0) throw new TypeError('timeoutMs and maxPending must be positive')
    this.capturePath = capturePath
    this.timeoutMs = timeoutMs
    this.maxPending = maxPending
    this.session = randomUUID()
    this.nextId = 1
    this.pending = new Map()
    this.buffer = ''
    this.stderrBuffer = ''
    this.closed = false
    this.closing = false
    this.fatal = null
    this.captureBusy = false
    this.closePromise = null
    this.processClose = new Promise((resolve) => { this.childCloseResolve = resolve })
    this.child = spawn(executable, args, { shell: false, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, ...env, METONIC_GPU_BRIDGE: bridge, METONIC_CAPTURE_PATH: capturePath } })
    this.child.stdout.setEncoding('utf8')
    this.child.stderr.setEncoding('utf8')
    this.child.stdout.on('data', (chunk) => this.#stdout(chunk))
    this.child.stderr.on('data', (chunk) => {
      const bytes = Buffer.concat([Buffer.from(this.stderrBuffer), Buffer.from(chunk)]).subarray(-16 * 1024)
      this.stderrBuffer = bytes.toString()
    })
    this.child.stdin.on('error', (error) => this.#fatal(error))
    this.child.on('error', (error) => this.#fatal(error))
    this.child.on('disconnect', () => this.#fatal(new Error('native child disconnected')))
    this.child.on('close', (code, signal) => { this.childCloseResolve?.({ code, signal }); if (!this.closing) this.#fatal(new Error(`native child exited (${code ?? signal})`)) })
  }

  get diagnostics() { return { session: this.session, stderr: this.stderrBuffer, fatal: this.fatal } }

  #stdout(chunk) {
    this.buffer += chunk.toString()
    if (Buffer.byteLength(this.buffer) > MAX_LINE) return this.#fatal(new Error('native stdout line exceeds 64 KiB'))
    while (true) {
      const newline = this.buffer.indexOf('\n')
      if (newline < 0) return
      const line = this.buffer.slice(0, newline).replace(/\r$/, '')
      this.buffer = this.buffer.slice(newline + 1)
      let response
      try { response = JSON.parse(line) } catch { return this.#fatal(new Error('invalid native JSON response')) }
      if (!response || response.version !== 1 || !Number.isInteger(response.id) || typeof response.ok !== 'boolean' || (!response.ok && typeof response.error !== 'string') || !Array.isArray(response.state) || response.state.length !== 8 || !response.state.every(Number.isInteger) || !Number.isInteger(response.frame) || response.frame < 0 || response.state[6] < 1 || response.state[6] > 2048 || response.state[7] < 1 || response.state[7] > 2048) return this.#fatal(new Error('invalid native response schema'))
      const item = this.pending.get(response.id)
      if (!item) return this.#fatal(new Error(`unknown native response id ${response.id}`))
      this.pending.delete(response.id)
      clearTimeout(item.timer)
      item.signal?.removeEventListener('abort', item.abort)
      item.resolve(response)
    }
  }

  #fatal(error) {
    if (this.closed) return
    this.fatal ??= error
    this.closed = true
    if (this.child.exitCode === null) this.child.kill('SIGTERM')
    for (const item of this.pending.values()) { clearTimeout(item.timer); item.signal?.removeEventListener('abort', item.abort); item.reject(this.fatal) }
    this.pending.clear()
  }

  request(op, args = {}, options = {}) { return this.#request(op, args, options, false) }

  #request(op, args = {}, { signal } = {}, internal = false) {
    if (this.closed || this.closing) return Promise.reject(this.fatal ?? new Error('native client is closed'))
    if (typeof op !== 'string' || (op === 'capture' && !internal)) return Promise.reject(new Error('invalid operation'))
    if (signal?.aborted) return Promise.reject(signal.reason ?? new Error('request aborted'))
    if (this.pending.size >= this.maxPending) return Promise.reject(new Error('native pending request limit reached'))
    if (!args || typeof args !== 'object' || Array.isArray(args)) return Promise.reject(new TypeError('request args must be an object'))
    for (const key of ['version', 'id', 'op']) if (Object.hasOwn(args, key)) return Promise.reject(new Error(`reserved request field: ${key}`))
    if (this.nextId > 0x7fffffff) return Promise.reject(new Error('native request id exhausted'))
    const id = this.nextId++
    let payload
    try { payload = JSON.stringify({ version: 1, id, op, ...args }) } catch (error) { return Promise.reject(error) }
    if (Buffer.byteLength(payload) > MAX_JSON) return Promise.reject(new Error('serialized request exceeds 4095 bytes'))
    return new Promise((resolve, reject) => {
      const abort = () => this.#fatal(signal.reason ?? new Error('request aborted'))
      const timer = setTimeout(() => this.#fatal(new Error(`native request timeout: ${id}`)), this.timeoutMs)
      this.pending.set(id, { resolve, reject, timer, signal, abort })
      signal?.addEventListener('abort', abort, { once: true })
      try { this.child.stdin.write(`${payload}\n`) } catch (error) { this.#fatal(error) }
    })
  }

  capture({ expected_revision, signal } = {}) {
    if (this.captureBusy) return Promise.reject(new Error('capture busy'))
    this.captureBusy = true
    const run = (async () => {
      const response = await this.#request('capture', expected_revision === undefined ? {} : { expected_revision }, { signal }, true)
      if (!response.ok) throw new Error(response.error ?? 'native capture failed')
      const rgba = await readFile(this.capturePath)
      const expected = response.state[6] * response.state[7] * 4
      if (rgba.length !== expected) throw new Error(`invalid RGBA length: ${rgba.length}, expected ${expected}`)
      return { response, rgba }
    })().finally(() => { this.captureBusy = false })
    return run
  }

  async close() {
    if (this.closePromise) return this.closePromise
    this.closePromise = (async () => {
      const deadline = Date.now() + 2000
      if (!this.closed) {
        const shutdown = this.#request('shutdown')
        this.closing = true
        let shutdownTimer
        try { await Promise.race([shutdown, new Promise((resolve) => { shutdownTimer = setTimeout(resolve, Math.max(0, deadline - Date.now())) })]) } catch {} finally { clearTimeout(shutdownTimer) }
        this.child.stdin.end()
      }
      let timer
      try {
        await Promise.race([this.processClose, new Promise((resolve) => { timer = setTimeout(() => { this.#fatal(new Error('native close timeout')); if (this.child.exitCode === null) this.child.kill('SIGTERM'); resolve() }, Math.max(0, deadline - Date.now())) })])
      } finally { clearTimeout(timer) }
      this.closed = true
    })()
    return this.closePromise
  }
}
