---
name: 本地 Web 应用右侧预览
description: 在 OpenCode 右侧 Review 窗格直接预览并操作本地 Web 应用/H5 工具。用于创建 iframe 预览页、修复「加载文件失败」与「Failed to fetch」、配置服务端 CORS 预检、以及让本地服务在系统重启后自动恢复（计划任务 + watchdog）。
---

# 本地 Web 应用右侧预览

## 适用场景

- 有一个本地 Web 服务（Node / Python / 静态服务器），想在 OpenCode 右侧 **Review 窗格**直接看和操作。
- 右侧显示 **「加载文件失败」**（通常是 `/api/fs/read/<file>` 返回 404）。
- 页面能显示，但点按钮报 **「Failed to fetch」**（沙箱 iframe 的 CORS 预检失败）。
- 希望 **系统重启后服务自动恢复**，不用手动启动。

## 核心原理（先读，避免踩坑）

1. OpenCode 右侧 Review 窗格可以渲染 **HTML 文件**（`text/html`），内部用 iframe + sandbox `allow-scripts allow-popups allow-forms allow-modals`。
2. **Markdown 渲染器会剥离 `<iframe>`**（DOMPurify 的 html profile 不含 iframe）。所以预览入口必须是 `.html` 文件，**不要**把 iframe 写进 `.md` 里。
3. Review 窗格的 iframe 是 **opaque origin**（sandbox 没有 `allow-same-origin`）。页面里的 `fetch` 打到本地端口属于跨域：
   - `GET` 简单请求可能直接通过；
   - `POST` + `Content-Type: application/json` 会先发 `OPTIONS` 预检，**服务端必须返回 CORS 头并对 OPTIONS 返回 204**，否则浏览器直接报 `Failed to fetch`。
4. `browser.md` 的 404 是「加载文件失败」的常见原因；创建它作为入口即可。

## 步骤

### 1. 确认服务与端口

```powershell
curl.exe -s http://127.0.0.1:<port>/api/health
```

记下端口（示例用 8770）和健康接口路径。

### 2. 创建 HTML 预览入口

复制 `templates/preview.html` 到项目根，把 `<port>` 换成实际端口。它内嵌全屏 iframe，并在服务离线时显示启动提示。

命名建议：`<tool>_preview.html`（如 `drama_preview.html`）。

### 3. 修复 `browser.md` 404

在项目根创建 `browser.md`，用 Markdown 链接指向预览页（**不要放 iframe**）：

```markdown
# 右侧预览

点击打开：[<tool>_preview.html](<tool>_preview.html)
```

### 4. 服务端加 CORS（修复 Failed to fetch）

参考 `templates/cors-snippet.md`。核心是：

- 所有 JSON 响应加：
  - `Access-Control-Allow-Origin: *`
  - `Access-Control-Allow-Methods: GET, POST, OPTIONS`
  - `Access-Control-Allow-Headers: Content-Type, Authorization`
  - `Access-Control-Max-Age: 86400`
- 收到 `OPTIONS` 时直接返回 `204` + 上述头。

### 5. 配置开机自启（可选）

复制并调整：

- `templates/start.cmd`：端口守卫 + watchdog 循环（纯 ASCII + CRLF）。
- `templates/install-autostart.ps1`：注册计划任务（登录触发）+ 启动文件夹快捷方式（后备）。

运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <path>\install-autostart.ps1
```

### 6. 验证清单

- [ ] `OPTIONS` 预检返回 204 且带 CORS 头
- [ ] 带 `Origin: null` 的 `POST` 返回 200
- [ ] 杀掉服务进程后，watchdog 在 5~10 秒内恢复
- [ ] 重启登录后端口自动监听
- [ ] `stop` 脚本同时杀掉 watchdog，否则会被自动拉起

## 故障排查

| 现象 | 原因 | 修复 |
|---|---|---|
| 右侧「加载文件失败」 | `/api/fs/read/browser.md` 404 | 在项目根创建 `browser.md` |
| 页面空白 | iframe 指向的服务未启动 | 启动服务；`preview.html` 会显示提示 |
| 按钮「Failed to fetch」 | 沙箱 iframe 的 CORS 预检失败 | 服务端加 CORS + OPTIONS 204 |
| 改完 CORS 仍报错 | 服务端没重启 | 重启 node/python 进程 |
| 重启后服务不在 | 未配置自启 | 运行 `install-autostart.ps1` |
| `stop` 后服务复活 | watchdog 没停 | 同时杀掉 `cmd` watchdog 进程 |
| 右侧仍显示旧页面 | 浏览器缓存 | `Ctrl+R` 刷新，或服务端加 `Cache-Control: no-store` |

更多细节见 `references/troubleshooting.md`。

## 约束

- `.ps1` 必须纯 ASCII（中文用 `\uXXXX` 或英文）；`.cmd` 用 CRLF。
- 不要把 API Key 写进技能、预览页或公开仓库。
- 端口避开已占用；先查 `Get-NetTCPConnection -State Listen`。
- 本技能只负责「右侧预览 + 自启」，不负责具体业务数据模型。

## 模板

- `templates/preview.html`：全屏 iframe + 离线提示
- `templates/start.cmd`：端口守卫 + watchdog
- `templates/install-autostart.ps1`：计划任务 + 启动文件夹
- `templates/cors-snippet.md`：Node / Python CORS 片段
- `references/troubleshooting.md`：排查手册
