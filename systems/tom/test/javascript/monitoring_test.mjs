import test from 'node:test'
import assert from 'node:assert/strict'
import vm from 'node:vm'
import fs from 'node:fs'

const source = fs.readFileSync(new URL('../../app/assets/javascripts/monitoring.js', import.meta.url), 'utf8')
function harness() {
  const listeners = new Map(), timers = [], calls = [], region = { children: [], querySelector() { return feedback }, replaceChildren(...v) { this.children = v } }
  let feedback = null, count = 0
  class Form {
    constructor() { this.dataset = {}; this.isConnected = true; this.button = { disabled: false }; this.secret = { value: 'private-token' } }
    querySelectorAll(selector) { return selector.includes('type="submit"') ? [this.button] : [this.secret] }
  }
  const emit = (name, event) => { for (const listener of listeners.get(name) || []) listener(event) }
  const document = { visibilityState: 'visible', activeElement: null,
    addEventListener(name, listener) { listeners.set(name, [...(listeners.get(name) || []), listener]) },
    getElementById(id) { return id === 'tom-feedback' ? region : null },
    createElement() { return { dataset: {}, setAttribute() {} } }, querySelector() { return feedback }
  }
  const window = { location: { origin: 'http://tom.test' }, addEventListener() {}, Turbo: { renderStreamMessage() {} } }
  const context = vm.createContext({ document, window, HTMLFormElement: Form, URL, location: { origin: 'http://tom.test' },
    crypto: { randomUUID: () => `operation-${++count}` }, queueMicrotask: fn => fn(), AbortSignal,
    setTimeout: fn => { const job = { fn }; timers.push(job); return job }, clearTimeout: job => { if (job) job.cancelled = true },
    fetch: async (url, options) => { calls.push({ url, options }); return { headers: new Headers({ 'Content-Type': 'text/vnd.turbo-stream.html' }), text: async () => '<turbo-stream />' } }
  })
  vm.runInContext(source, context)
  function begin(form = new Form()) {
    const detail = { url: new URL('http://tom.test/tenants'), fetchOptions: { method: 'POST', headers: { Accept: 'text/vnd.turbo-stream.html' } } }
    emit('turbo:before-fetch-request', { target: form, detail })
    return { form, operation: detail.fetchOptions.headers['X-TOM-Operation-ID'] }
  }
  async function stream(operation, nextFeedback) {
    let prevented = false, rendered = false
    const event = { target: { dataset: { operationId: operation } }, detail: { render: async () => { rendered = true; feedback = nextFeedback } }, preventDefault() { prevented = true } }
    emit('turbo:before-stream-render', event)
    if (!prevented) await event.detail.render({ target: 'tom-feedback' })
    return { prevented, rendered }
  }
  return { emit, begin, stream, Form, calls, region, timers, window, failFetch: () => { context.fetch = async () => { throw new Error("offline") } }, setFeedback: f => { feedback = f } }
}

test('a stream error response is left to Turbo; a non-stream proxy 500 keeps the form and blocks repeats', () => {
  const h = harness(), { form } = h.begin()
  let prevented = false
  h.emit('turbo:before-fetch-response', { target: form, detail: { fetchResponse: { response: { status: 500, headers: new Headers({ 'Content-Type': 'text/vnd.turbo-stream.html' }) } } }, preventDefault() { prevented = true } })
  assert.equal(prevented, false)
  h.emit('turbo:before-fetch-response', { target: form, detail: { fetchResponse: { response: { status: 500, headers: new Headers({ 'Content-Type': 'text/html' }) } } }, preventDefault() { prevented = true } })
  assert.equal(prevented, true)
  assert.equal(form.isConnected, true)
  assert.equal(form.dataset.completionUncertain, 'true')
  assert.equal(form.secret.value, '')
  assert.equal(form.button.disabled, true)
  assert.match(h.region.children[0].textContent, /view is preserved/)
})

test('late operation streams cannot overwrite newer feedback or a newly loaded page', async () => {
  const h = harness(), first = h.begin(), second = h.begin()
  assert.equal((await h.stream(first.operation, null)).prevented, true)
  assert.equal((await h.stream(second.operation, null)).rendered, true)
  h.emit('turbo:load', {})
  assert.equal((await h.stream(second.operation, null)).prevented, true)
})

test('network interruption provides safe feedback without a page replacement or replay', () => {
  const h = harness(), { form } = h.begin()
  h.emit('turbo:fetch-request-error', { target: form, preventDefault() {} })
  assert.match(h.region.children[0].textContent, /completion is unknown/)
  assert.equal(h.calls.length, 0)
  assert.equal(form.isConnected, true)
})

test('completion checks are bounded, same-origin GET requests and never replay a mutation', async () => {
  const h = harness(), { operation } = h.begin()
  const feedback = { dataset: { outcome: 'unknown', checkUrl: '/operations/status?token=opaque' } }
  h.window.Turbo.renderStreamMessage = () => h.stream(operation, feedback)
  await h.stream(operation, feedback)
  for (let i = 0; i < 6; i++) {
    const timer = h.timers.shift()
    if (!timer) break
    if (!timer.cancelled) await timer.fn()
    await new Promise(resolve => setImmediate(resolve))
  }
  assert.equal(h.calls.length, 3)
  assert.ok(h.calls.every(call => call.url.startsWith('http://tom.test/operations/status?') && !call.options.method))
  assert.ok(h.calls.every(call => call.options.credentials === 'same-origin' && call.options.redirect === 'error'))
})

test('foreign check URLs and checks from an abandoned page are not fetched', async () => {
  const h = harness(), { operation } = h.begin()
  await h.stream(operation, { dataset: { checkUrl: 'https://foreign.test/operations/status', outcome: 'unknown' } })
  assert.equal(h.timers.length, 0)
  await h.stream(operation, { dataset: { checkUrl: '/operations/status?token=opaque', outcome: 'unknown' } })
  h.emit('turbo:before-visit', {})
  for (const timer of h.timers) if (!timer.cancelled) await timer.fn()
  assert.equal(h.calls.length, 0)
})

test('a failed completion check preserves its manual link and original reference', async () => {
  const h = harness(), { operation } = h.begin(), messages = []
  const feedback = { dataset: { operationId: operation, outcome: 'unknown', checkUrl: '/operations/status?token=opaque' }, querySelector() { return null }, append(message) { messages.push(message) } }
  h.failFetch()
  await h.stream(operation, feedback)
  await h.timers.shift().fn()
  assert.equal(feedback.dataset.checkUrl, '/operations/status?token=opaque')
  assert.match(messages[0].textContent, /Completion is unknown/)
  assert.equal(h.region.children.length, 0)
})
