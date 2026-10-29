// Capture network / console / exception events from a CDP page target.
// Usage: node cdp-monitor.mjs --port 9222 --seconds 5 [--target <id>] [--filter <substr>]

const args = process.argv.slice(2)
const argOf = (name, dflt) => {
  const i = args.indexOf(name)
  return i >= 0 && args[i + 1] ? args[i + 1] : dflt
}

const PORT = Number(argOf("--port", 9222))
const SECONDS = Math.max(1, Math.min(60, Number(argOf("--seconds", 5))))
const TARGET = argOf("--target", "")
const FILTER = argOf("--filter", "")

const out = { requests: [], console: [], exceptions: [], logs: [] }
const LIMIT = 300
const reqs = new Map()

function push(arr, item) {
  if (arr.length < LIMIT) arr.push(item)
}

function textOf(arg) {
  if (!arg) return ""
  if (arg.value !== undefined) return String(arg.value)
  if (arg.description !== undefined) return String(arg.description)
  return arg.type ? `<${arg.type}>` : ""
}

async function main() {
  let list
  try {
    const res = await fetch(`http://127.0.0.1:${PORT}/json/list`)
    list = await res.json()
  } catch (e) {
    throw new Error(`cannot reach CDP on port ${PORT}: ${e.message}`)
  }
  const pages = (Array.isArray(list) ? list : []).filter((t) => t.type === "page")
  const page = TARGET ? pages.find((t) => t.id === TARGET) : pages[0]
  if (!page) throw new Error(`no page target on port ${PORT}`)

  const ws = new WebSocket(page.webSocketDebuggerUrl)
  let nextId = 1
  const send = (method, params = {}) => {
    try { ws.send(JSON.stringify({ id: nextId++, method, params })) } catch {}
  }

  const done = new Promise((resolve) => {
    const timer = setTimeout(() => {
      try { ws.close() } catch {}
      resolve()
    }, SECONDS * 1000)
    ws.onclose = () => { clearTimeout(timer); resolve() }
    ws.onerror = () => { clearTimeout(timer); resolve() }
  })

  ws.onopen = () => {
    send("Network.enable")
    send("Runtime.enable")
    send("Log.enable")
    send("Page.enable")
  }

  ws.onmessage = (ev) => {
    let msg
    try { msg = JSON.parse(ev.data) } catch { return }
    if (!msg.method) return
    const p = msg.params || {}
    switch (msg.method) {
      case "Network.requestWillBeSent": {
        const r = p.request || {}
        const rec = {
          id: p.requestId,
          url: r.url || "",
          method: r.method || "",
          type: p.type || "",
          status: null,
          mime: "",
          durationMs: null,
          failed: false,
        }
        reqs.set(p.requestId, rec)
        if (!FILTER || rec.url.includes(FILTER)) push(out.requests, rec)
        break
      }
      case "Network.responseReceived": {
        const rec = reqs.get(p.requestId)
        if (rec) {
          rec.status = p.response ? p.response.status : null
          rec.mime = p.response ? p.response.mimeType : ""
        }
        break
      }
      case "Network.loadingFinished": {
        const rec = reqs.get(p.requestId)
        if (rec && rec._start !== undefined) rec.durationMs = Math.round(p.timestamp * 1000 - rec._start)
        break
      }
      case "Network.loadingFailed": {
        const rec = reqs.get(p.requestId)
        if (rec) { rec.failed = true; rec.error = p.errorText || "" }
        break
      }
      case "Runtime.consoleAPICalled": {
        push(out.console, {
          level: p.type || "log",
          text: (p.args || []).map(textOf).join(" "),
          time: p.timestamp ? Math.round(p.timestamp) : null,
        })
        break
      }
      case "Runtime.exceptionThrown": {
        const d = p.exceptionDetails || {}
        push(out.exceptions, {
          text: d.text || (d.exception && d.exception.description) || "exception",
          url: d.url || "",
          line: d.lineNumber,
          column: d.columnNumber,
        })
        break
      }
      case "Log.entryAdded": {
        const e = p.entry || {}
        push(out.logs, {
          level: e.level || "",
          text: e.text || "",
          source: e.source || "",
          url: e.url || "",
        })
        break
      }
    }
  }

  // record request start times via a separate listener (kept simple: use message order)
  ws.addEventListener("message", (ev) => {
    try {
      const msg = JSON.parse(ev.data)
      if (msg.method === "Network.requestWillBeSent") {
        const rec = reqs.get(msg.params.requestId)
        if (rec) rec._start = msg.params.timestamp * 1000
      }
    } catch {}
  })

  await done
  for (const r of out.requests) delete r._start
  console.log(JSON.stringify({ port: PORT, seconds: SECONDS, target: page.id, url: page.url, ...out }, null, 2))
}

main().catch((e) => {
  console.log(JSON.stringify({ error: String(e && e.message || e) }))
  process.exit(1)
})
