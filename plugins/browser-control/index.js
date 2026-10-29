import { Plugin } from "@opencode/plugin"
import { execFile } from "node:child_process"
import { promisify } from "node:util"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const execFileAsync = promisify(execFile)
const HERE = path.dirname(fileURLToPath(import.meta.url))

function findRoot(start) {
  let dir = start
  for (let i = 0; i < 8; i++) {
    if (fs.existsSync(path.join(dir, "tools", "cdp.ps1"))) return dir
    const parent = path.dirname(dir)
    if (parent === dir) break
    dir = parent
  }
  return path.resolve(start, "..", "..")
}

const ROOT = findRoot(HERE)
const CDP = path.join(ROOT, "tools", "cdp.ps1")
const MONITOR = path.join(HERE, "cdp-monitor.mjs")
const TMP = path.join(ROOT, "temp")

const NODE_CANDIDATES = [
  process.env.NODE_EXE,
  "D:\\Tuanjie Cowork\\cli\\bin\\win32-x64\\node.exe",
  "C:\\Program Files\\nodejs\\node.exe",
].filter(Boolean)

function findNode() {
  for (const p of NODE_CANDIDATES) {
    if (p === "node" || fs.existsSync(p)) return p
  }
  return "node"
}

function ensureTmp() {
  if (!fs.existsSync(TMP)) fs.mkdirSync(TMP, { recursive: true })
}

function stamp() {
  return new Date().toISOString().replace(/[:.]/g, "-")
}

async function runCdp(args, signal) {
  if (!fs.existsSync(CDP)) {
    throw new Error(`cdp.ps1 not found: ${CDP}`)
  }
  const { stdout, stderr } = await execFileAsync(
    "powershell.exe",
    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", CDP, ...args],
    { cwd: ROOT, windowsHide: true, maxBuffer: 16 * 1024 * 1024, signal },
  )
  const out = String(stdout || "").trim()
  if (!out && stderr) throw new Error(String(stderr).trim())
  return out
}

function commonTarget(input) {
  return input && input.target_id ? ["-TargetId", String(input.target_id)] : []
}

function tool(name, description, input, run) {
  return { name, description, input, execute: run }
}

export default Plugin.define({
  id: "browser-control",
  async setup(ctx) {
    await ctx.tool.transform((editor) => {
      editor.namespace({
        name: "cdp",
        description: "Control and monitor a local Edge/Chrome over the Chrome DevTools Protocol (CDP). Requires a browser started with --remote-debugging-port=9222.",
      })

      editor.add(tool("cdp_list",
        "List open page targets in the CDP browser.",
        { type: "object", properties: { port: { type: "number" } }, additionalProperties: false },
        async (input) => {
          const out = await runCdp(["-Op", "List", "-Port", String(input.port || 9222)])
          return { content: out || "(no page targets)" }
        },
      ))

      editor.add(tool("cdp_open",
        "Open a new tab at a URL in the CDP browser.",
        { type: "object", properties: { url: { type: "string" }, port: { type: "number" } }, required: ["url"], additionalProperties: false },
        async (input) => {
          const out = await runCdp(["-Op", "Open", "-Port", String(input.port || 9222), "-Url", input.url])
          return { content: out }
        },
      ))

      editor.add(tool("cdp_nav",
        "Navigate an existing tab to a URL.",
        { type: "object", properties: { url: { type: "string" }, port: { type: "number" }, target_id: { type: "string" } }, required: ["url"], additionalProperties: false },
        async (input) => {
          const out = await runCdp(["-Op", "Nav", "-Port", String(input.port || 9222), "-Url", input.url, ...commonTarget(input)])
          return { content: out }
        },
      ))

      editor.add(tool("cdp_eval",
        "Evaluate JavaScript in a tab and return the value (JSON-encoded when not a string).",
        { type: "object", properties: { js: { type: "string" }, port: { type: "number" }, target_id: { type: "string" } }, required: ["js"], additionalProperties: false },
        async (input) => {
          ensureTmp()
          const file = path.join(TMP, `cdp_eval_${stamp()}.js`)
          fs.writeFileSync(file, input.js, "utf8")
          try {
            const out = await runCdp(["-Op", "Eval", "-Port", String(input.port || 9222), "-EvalFile", file, ...commonTarget(input)])
            return { content: out }
          } finally {
            try { fs.unlinkSync(file) } catch {}
          }
        },
      ))

      editor.add(tool("cdp_click",
        "Click at viewport coordinates in a tab.",
        { type: "object", properties: { x: { type: "number" }, y: { type: "number" }, port: { type: "number" }, target_id: { type: "string" } }, required: ["x", "y"], additionalProperties: false },
        async (input) => {
          const out = await runCdp(["-Op", "Click", "-Port", String(input.port || 9222), "-ClickX", String(input.x), "-ClickY", String(input.y), ...commonTarget(input)])
          return { content: out }
        },
      ))

      editor.add(tool("cdp_type",
        "Type text into the focused input/textarea/contenteditable of a tab.",
        { type: "object", properties: { text: { type: "string" }, port: { type: "number" }, target_id: { type: "string" } }, required: ["text"], additionalProperties: false },
        async (input) => {
          ensureTmp()
          const file = path.join(TMP, `cdp_text_${stamp()}.txt`)
          fs.writeFileSync(file, input.text, "utf8")
          try {
            const out = await runCdp(["-Op", "Type", "-Port", String(input.port || 9222), "-TextFile", file, ...commonTarget(input)])
            return { content: out }
          } finally {
            try { fs.unlinkSync(file) } catch {}
          }
        },
      ))

      editor.add(tool("cdp_key",
        "Press a key in a tab: Enter, Tab, or Escape.",
        { type: "object", properties: { key: { type: "string", enum: ["Enter", "Tab", "Escape"] }, port: { type: "number" }, target_id: { type: "string" } }, required: ["key"], additionalProperties: false },
        async (input) => {
          const out = await runCdp(["-Op", "Key", "-Port", String(input.port || 9222), "-Key", input.key, ...commonTarget(input)])
          return { content: out }
        },
      ))

      editor.add(tool("cdp_shot",
        "Capture a PNG screenshot of a tab and save it to a file.",
        { type: "object", properties: { out_path: { type: "string" }, width: { type: "number" }, height: { type: "number" }, port: { type: "number" }, target_id: { type: "string" } }, additionalProperties: false },
        async (input) => {
          ensureTmp()
          const outPath = input.out_path || path.join(TMP, `cdp_shot_${stamp()}.png`)
          const args = ["-Op", "Shot", "-Port", String(input.port || 9222), "-OutPath", outPath]
          if (input.width && input.height) args.push("-Width", String(input.width), "-Height", String(input.height))
          const out = await runCdp([...args, ...commonTarget(input)])
          return { content: out }
        },
      ))

      editor.add(tool("cdp_wait_for",
        "Poll a JavaScript expression in a tab until it is truthy (or timeout).",
        { type: "object", properties: { js: { type: "string" }, timeout_sec: { type: "number" }, port: { type: "number" }, target_id: { type: "string" } }, required: ["js"], additionalProperties: false },
        async (input) => {
          ensureTmp()
          const file = path.join(TMP, `cdp_wait_${stamp()}.js`)
          fs.writeFileSync(file, input.js, "utf8")
          try {
            const out = await runCdp(["-Op", "WaitFor", "-Port", String(input.port || 9222), "-EvalFile", file, "-TimeoutSec", String(input.timeout_sec || 60), ...commonTarget(input)])
            return { content: out }
          } finally {
            try { fs.unlinkSync(file) } catch {}
          }
        },
      ))

      editor.add(tool("cdp_preview",
        "Create or update a full-screen HTML preview page for a local web service, plus a browser.md entry, so the OpenCode Review pane can show it. Returns the created file paths.",
        {
          type: "object",
          properties: {
            port: { type: "number", description: "local service port, default 8770" },
            name: { type: "string", description: "preview file name, default drama_preview.html" },
          },
          additionalProperties: false,
        },
        async (input) => {
          const port = input.port || 8770
          const fileName = input.name || "drama_preview.html"
          const filePath = path.join(ROOT, fileName)
          const html = `<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Preview</title>
<style>
  html,body{margin:0;padding:0;height:100%;background:#171310;overflow:hidden}
  iframe{display:block;width:100%;height:100vh;border:0;background:#171310}
  .fallback{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;color:#e8dcc4;font:14px/1.7 "Microsoft YaHei",Consolas,monospace;text-align:center;padding:24px}
  .hide{display:none}
</style>
</head>
<body>
  <iframe id="app" src="http://127.0.0.1:${port}/" title="Preview"></iframe>
  <div id="fallback" class="fallback hide"><div>本地服务未启动：请先运行启动脚本，然后刷新本页。</div></div>
<script>
  (function(){
    let alive=false;
    fetch('http://127.0.0.1:${port}/api/health',{cache:'no-store'})
      .then(r=>r.json()).then(j=>{alive=!!(j&&j.ok)}).catch(()=>{alive=false})
      .finally(()=>{if(!alive)document.getElementById('fallback').classList.remove('hide')});
    setTimeout(()=>{if(!alive)document.getElementById('fallback').classList.remove('hide')},5000);
  })();
</script>
</body>
</html>
`
          fs.writeFileSync(filePath, html, "utf8")
          const entry = path.join(ROOT, "browser.md")
          if (!fs.existsSync(entry)) {
            fs.writeFileSync(entry, `点击打开：[${fileName}](${fileName})\n`, "utf8")
          }
          return { content: `preview: ${filePath}\nentry: ${entry}\nurl: http://127.0.0.1:${port}/` }
        },
      ))

      editor.add(tool("cdp_monitor",
        "Monitor a tab for N seconds and return captured network requests, console messages, exceptions, and browser logs as JSON.",
        {
          type: "object",
          properties: {
            seconds: { type: "number", description: "capture duration, default 5" },
            port: { type: "number" },
            target_id: { type: "string" },
            url_filter: { type: "string", description: "only keep requests whose URL contains this substring" },
          },
          additionalProperties: false,
        },
        async (input, context) => {
          const args = [
            MONITOR,
            "--port", String(input.port || 9222),
            "--seconds", String(input.seconds || 5),
          ]
          if (input.target_id) args.push("--target", String(input.target_id))
          if (input.url_filter) args.push("--filter", String(input.url_filter))
          const { stdout, stderr } = await execFileAsync(findNode(), args, {
            cwd: ROOT,
            windowsHide: true,
            maxBuffer: 16 * 1024 * 1024,
            signal: context && context.signal,
          })
          const out = String(stdout || "").trim()
          if (!out && stderr) throw new Error(String(stderr).trim())
          return { content: out }
        },
      ))
    })
  },
})
