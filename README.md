# OpenCode Extensions

> Local web preview + real browser control for **OpenCode V2**.

Two reusable extensions for [OpenCode](https://opencode.ai):

| Part | What it does |
|---|---|
| **`skills/local-web-preview`** | A skill that teaches the agent to preview a local web app in OpenCode's right-hand Review pane, fix `加载文件失败` / `Failed to fetch`, add CORS, and auto-start the service after reboot. |
| **`plugins/browser-control`** | A plugin that drives a real Edge/Chrome over the Chrome DevTools Protocol (CDP), captures network/console/exceptions, generates a right-pane preview page, and optionally embeds a GUI panel. |

## Features

- **Right-pane preview** — full-screen `iframe` page + `browser.md` entry, so a local tool appears inside OpenCode.
- **Real browser control** — list/open/navigate/click/type/key/eval/screenshot over CDP.
- **Monitoring** — capture `Network.*`, `Runtime.consoleAPICalled`, `Runtime.exceptionThrown`, and `Log.entryAdded` as JSON.
- **CORS guidance** — fixes the sandboxed-iframe `OPTIONS` preflight problem.
- **Auto-start** — optional scheduled task + startup shortcut + watchdog for Windows.

## Requirements

- OpenCode **V2**
- **Windows** (PowerShell 5.1+, Edge or Chrome)
- Node.js **18+** (for `cdp-monitor.mjs`)

> The CDP client `tools/cdp.ps1` is Windows-only. The skill's HTML preview part is cross-platform.

## Install

### 1. Skill

Copy `skills/local-web-preview` into your global skills directory:

```powershell
# Windows
Copy-Item skills\local-web-preview "$env:USERPROFILE\.config\opencode\skills\local-web-preview" -Recurse -Force
```

```bash
# macOS / Linux (if you use the HTML preview part only)
cp -R skills/local-web-preview ~/.config/opencode/skills/
```

Or reference the folder from `opencode.json`:

```jsonc
{
  "skills": ["./opencode-extensions/skills"]
}
```

### 2. Plugin

Keep `plugins/browser-control` and `tools/cdp.ps1` in the same project root, then register the plugin:

```jsonc
{
  "plugins": ["D:\\path\\to\\opencode-extensions\\plugins\\browser-control"]
}
```

Restart OpenCode Desktop so the GUI part loads.

## Usage

### Real browser (CDP)

Start Edge with a debugging port:

```powershell
& 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' `
  --remote-debugging-port=9222 `
  --user-data-dir=D:\temp\edge_cdp_profile `
  http://127.0.0.1:8770/
```

Then use the tools:

| Tool | Description |
|---|---|
| `cdp_list` | List page targets |
| `cdp_open` | Open a new tab |
| `cdp_nav` | Navigate |
| `cdp_eval` | Evaluate JavaScript |
| `cdp_click` | Click at coordinates |
| `cdp_type` | Type into the focused field |
| `cdp_key` | Press Enter / Tab / Escape |
| `cdp_shot` | Capture a PNG screenshot |
| `cdp_wait_for` | Poll an expression until truthy |
| `cdp_monitor` | Capture network / console / exceptions / logs |

### Right-pane preview

```
cdp_preview { "port": 8770 }
```

Creates `<project>/drama_preview.html` and `browser.md`. Open the HTML file in OpenCode's Review pane.

### GUI panel

After restarting Desktop, run **“打开剧情编辑器”** from the command palette, or pick **剧情编辑器** in the right-side `+` menu.

## How it works

1. OpenCode's Review pane renders `.html` files in a sandboxed iframe.
2. Markdown renderers strip `<iframe>` (DOMPurify), so the preview entry must be an `.html` file.
3. A sandboxed iframe has an opaque origin, so `POST` + JSON triggers an `OPTIONS` preflight. The local server must return CORS headers and `204` for `OPTIONS`.
4. `tools/cdp.ps1` speaks CDP over `ClientWebSocket`; `cdp-monitor.mjs` uses Node's global `WebSocket`.

See [`skills/local-web-preview/references/troubleshooting.md`](skills/local-web-preview/references/troubleshooting.md) for detailed fixes.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Right pane says `加载文件失败` | Create `browser.md` in the project root |
| Buttons say `Failed to fetch` | Add CORS headers + `OPTIONS 204` to the server |
| Preview is blank | Start the local service; the page shows a hint |
| `cdp_list` cannot connect | Start Edge with `--remote-debugging-port=9222` |
| Stop script keeps restarting | Kill the watchdog `cmd` process too |

## Security

- This repository contains **no API keys**.
- Keep local config such as `ai_config.json` out of version control.
- `.gitignore` already excludes `node_modules/`, `temp/`, `backups/`, and `*.log`.

## License

MIT — see [LICENSE](LICENSE).
