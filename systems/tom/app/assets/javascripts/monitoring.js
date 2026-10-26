// Response streams only: no shared browser channel, server-side cache or command replay.
let activeOperation = null
let activeForm = null
let generation = 0
let timer = null
let checks = 0
const streamType = "text/vnd.turbo-stream.html"

function stopChecks() {
  clearTimeout(timer)
  timer = null
  generation += 1
}

function localFailure(message) {
  const region = document.getElementById("tom-feedback")
  if (!region) return
  const text = document.createElement("p")
  text.className = "mb-6 rounded-xl border border-amber-200 bg-amber-50 p-4"
  text.setAttribute("role", "status")
  text.textContent = message
  const existing = region.querySelector("[data-check-url]")
  if (existing && existing.dataset.operationId === activeOperation) {
    existing.querySelector("[data-connection-failure]")?.remove()
    text.dataset.connectionFailure = "true"
    existing.append(text)
  } else {
    region.replaceChildren(text)
  }
}

function protectForm(outcome) {
  if (!activeForm?.isConnected) return
  activeForm.querySelectorAll('input[name="token"], input[name="code"], input[type="password"]').forEach(input => { input.value = "" })
  if (outcome === "unknown" || outcome === "accepted") {
    activeForm.dataset.completionUncertain = "true"
    // Turbo restores submit buttons at submit-end; run once more after its cleanup.
    queueMicrotask(() => activeForm?.querySelectorAll('[type="submit"]').forEach(button => { button.disabled = true }))
  }
}

async function checkCompletion(url, version) {
  if (version !== generation || checks >= 3 || document.visibilityState === "hidden") return
  checks += 1
  try {
    const response = await fetch(url, { headers: { Accept: streamType, "X-TOM-Operation-ID": activeOperation }, credentials: "same-origin", cache: "no-store", redirect: "error", signal: AbortSignal.timeout(4000) })
    if (version !== generation) return
    if (response.headers.get("Content-Type")?.includes(streamType)) {
      window.Turbo.renderStreamMessage(await response.text())
    } else {
      localFailure("Completion could not be checked. Do not submit again until its status is known.")
    }
  } catch {
    if (version === generation) localFailure("The connection is unavailable. Completion is unknown; do not submit the action again yet.")
  }
}

function scheduleCheck() {
  const feedback = document.querySelector("#tom-feedback [data-check-url]")
  const url = feedback?.dataset.checkUrl
  if (!url || checks >= 3) return
  const parsed = new URL(url, window.location.origin)
  if (parsed.origin !== location.origin || parsed.pathname !== "/operations/status") return
  const version = generation
  timer = setTimeout(() => checkCompletion(parsed.href, version), 1200)
}

document.addEventListener("submit", event => {
  if (event.target.dataset.completionUncertain === "true") {
    event.preventDefault()
    event.stopImmediatePropagation()
  }
}, true)

document.addEventListener("turbo:before-fetch-request", event => {
  const form = event.target instanceof HTMLFormElement ? event.target : null
  const url = new URL(event.detail.url, location.origin)
  if (url.pathname === "/operations/status") {
    if (activeOperation) event.detail.fetchOptions.headers["X-TOM-Operation-ID"] = activeOperation
    return
  }
  const acceptsStream = event.detail.fetchOptions.headers.Accept?.includes(streamType)
  if (!form && !acceptsStream) return
  stopChecks()
  checks = 0
  activeOperation = crypto.randomUUID()
  activeForm = form
  event.detail.fetchOptions.headers["X-TOM-Operation-ID"] = activeOperation
})

// Turbo's stream observer accepts stream content regardless of HTTP success status.
// Intercept non-stream proxy/server failures before Turbo can replace the current page.
document.addEventListener("turbo:before-fetch-response", event => {
  const response = event.detail.fetchResponse.response
  if (event.target instanceof HTMLFormElement && event.target === activeForm && response.status >= 400 && !response.headers.get("Content-Type")?.includes(streamType)) {
    event.preventDefault()
    protectForm("unknown")
    localFailure("The server could not confirm this request. Your view is preserved; do not submit the action again until its status is known.")
  }
})

document.addEventListener("turbo:fetch-request-error", event => {
  event.preventDefault()
  if (event.target instanceof HTMLFormElement && event.target !== activeForm) return
  protectForm("unknown")
  localFailure("The connection was interrupted. Your view is preserved, but completion is unknown. Check the result before submitting again.")
})

document.addEventListener("turbo:before-stream-render", event => {
  const operation = event.target.dataset.operationId
  if (operation && operation !== activeOperation) {
    event.preventDefault()
    return
  }
  const original = event.detail.render
  event.detail.render = async stream => {
    const focused = document.activeElement
    const id = focused?.id
    const start = focused?.selectionStart
    const end = focused?.selectionEnd
    await original(stream)
    if (id && !focused.isConnected) {
      const replacement = document.getElementById(id)
      replacement?.focus({ preventScroll: true })
      if (typeof replacement?.setSelectionRange === "function" && typeof start === "number") {
        try { replacement.setSelectionRange(start, end) } catch { /* non-text input */ }
      }
    }
    if (stream.target === "tom-feedback") {
      const feedback = document.querySelector("#tom-feedback [data-outcome]")
      protectForm(feedback?.dataset.outcome)
      clearTimeout(timer)
      scheduleCheck()
    }
  }
})

document.addEventListener("turbo:submit-end", () => {
  if (activeForm?.dataset.completionUncertain === "true") protectForm("unknown")
})
document.addEventListener("turbo:before-visit", stopChecks)
document.addEventListener("turbo:load", () => {
  stopChecks()
  activeOperation = null
  activeForm = null
  checks = 0
})
window.addEventListener("pagehide", stopChecks)
