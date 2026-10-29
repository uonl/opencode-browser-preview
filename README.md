# OpenCode Extensions · 本地 Web 预览 + 浏览器控制

两个可复用的 OpenCode 扩展：

1. **`skills/local-web-preview`** — 技能：在 OpenCode 右侧 Review 窗格预览本地 Web 应用，修复「加载文件失败」「Failed to fetch」，配置 CORS 与开机自启。
2. **`plugins/browser-control`** — 插件：通过 CDP 操控真实 Edge/Chrome，并采集网络/控制台/异常；同时提供右侧预览页生成与 GUI 内嵌面板。

## 目录

```
opencode-extensions/
├── skills/
│   └── local-web-preview/
│       ├── SKILL.md
│       ├── templates/
│       │   ├── preview.html
│       │   ├── start.cmd
│       │   ├── install-autostart.ps1
│       │   └── cors-snippet.md
│       └── references/troubleshooting.md
├── plugins/
│   └── browser-control/
│       ├── index.js              # server 工具
│       ├── cdp-monitor.mjs       # 网络/控制台采集
│       ├── gui-experimental.cjs  # 右侧内嵌面板
│       └── package.json
└── tools/
    └── cdp.ps1                   # CDP 客户端（插件依赖）
```

## 安装

### 技能

复制到全局技能目录：

```bash
# Windows (XDG_CONFIG_HOME 可能不同)
copy skills\local-web-preview "%USERPROFILE%\.config\opencode\skills\local-web-preview" /E
```

或在项目的 `opencode.json` 里加：

```jsonc
{ "skills": ["./opencode-extensions/skills"] }
```

### 插件

1. 把 `plugins/browser-control` 和 `tools/cdp.ps1` 放到同一项目根下（保持 `tools/cdp.ps1` 相对位置）。
2. 在 `opencode.json` 注册插件：

```jsonc
{
  "plugins": ["D:\\path\\to\\opencode-extensions\\plugins\\browser-control"]
}
```

3. 重启 OpenCode 桌面应用（GUI 面板需要重新加载）。

## 使用

### 真实浏览器（CDP）

先启动带调试端口的 Edge：

```powershell
& 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' `
  --remote-debugging-port=9222 `
  --user-data-dir=D:\temp\edge_cdp_profile `
  http://127.0.0.1:8770/
```

工具：

| 工具 | 作用 |
|---|---|
| `cdp_list` | 列出页面标签 |
| `cdp_open` / `cdp_nav` | 新开 / 导航 |
| `cdp_eval` | 执行 JS |
| `cdp_click` / `cdp_type` / `cdp_key` | 交互 |
| `cdp_shot` | 截图 |
| `cdp_wait_for` | 轮询表达式 |
| `cdp_monitor` | 采集网络/console/异常/日志 |

### 右侧预览

```
cdp_preview { "port": 8770 }
```

生成 `<项目根>/drama_preview.html` 和 `browser.md`，在 OpenCode 右侧打开即可。

### GUI 内嵌面板

重启桌面应用后，命令面板执行「打开剧情编辑器」，或在右侧 `+` 菜单选择。

> 插件 id 为 `browser-control`，面板 key 为 `browser-control:web`。

## 安全

- 本仓库**不包含任何 API Key**。
- `ai_config.json` 等本地配置文件不要提交。
- `.gitignore` 已排除 `node_modules/`、`temp/`、`backups/`、`*.log`。

## 兼容性

- OpenCode V2（`@opencode/plugin`）
- Windows（PowerShell 5.1+、Edge/Chrome）
- 插件依赖 `tools/cdp.ps1`，请保持相对路径不变

## 许可

MIT
