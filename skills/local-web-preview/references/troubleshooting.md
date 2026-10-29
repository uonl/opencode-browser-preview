# 排查手册

## 1. 右侧显示「加载文件失败」

**日志特征**：`GET /api/fs/read/browser.md -> 404`

OpenCode 右侧某个标签在读取项目根目录的 `browser.md`。该文件不存在时就会报这个错。

**修复**：在项目根创建 `browser.md`，内容放一个指向预览页的 Markdown 链接：

```markdown
点击打开：[my_preview.html](my_preview.html)
```

不要在里面放 `<iframe>`——Markdown 渲染器会剥离它。

## 2. 右侧预览页空白

- 确认预览页是 `.html` 文件，而不是 `.md`。
- 确认 iframe 的 `src` 端口与服务实际端口一致。
- 确认服务正在监听：`Get-NetTCPConnection -State Listen -LocalPort <port>`。
- 打开预览页的源代码，确认 iframe 没有被改坏。

## 3. 页面能显示，但按钮报「Failed to fetch」

**原因**：Review 窗格的 iframe 是 opaque origin（sandbox 无 `allow-same-origin`），`POST` + JSON 触发 `OPTIONS` 预检，服务端没返回 CORS 头。

**修复**：
1. 服务端所有 JSON 响应加 CORS 头（见 `templates/cors-snippet.md`）。
2. 收到 `OPTIONS` 返回 `204`。
3. **重启服务**（改代码不会自动生效）。
4. 刷新右侧页面。

**验证**：

```bash
curl.exe -i -X OPTIONS http://127.0.0.1:<port>/api/test \
  -H "Origin: null" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: content-type"
```

期望：`204 No Content` + `Access-Control-Allow-Origin: *`。

## 4. 改完 CORS 仍报错

- 服务进程没重启（Node/Python 不会热重载）。
- 浏览器缓存了旧页面：`Ctrl+R` 或服务端加 `Cache-Control: no-store`。
- 预览页的 iframe 指向了旧端口。
- 有多个服务实例抢同一个端口（先 `Get-NetTCPConnection` 查 PID）。

## 5. 系统重启后服务不在

- 没有配置自启：运行 `templates/install-autostart.ps1`。
- 计划任务被禁用：`Get-ScheduledTask -TaskName <name>` 查看状态。
- 启动器路径含中文或空格：确认计划任务参数里的引号正确（`/c ""path""`）。
- 启动器自身有端口守卫，但服务没起来：查看 `monitor.log`。

## 6. `stop` 之后服务又活了

watchdog 的 `cmd` 进程还在，5 秒后会把 node 重新拉起。

**修复**：停止脚本同时杀两类进程：

```powershell
$targets = Get-CimInstance Win32_Process | Where-Object {
  $_.Name -eq "node.exe" -and $_.CommandLine -like "*<service>*server.mjs*"
}
$watch = Get-CimInstance Win32_Process | Where-Object {
  $_.Name -eq "cmd.exe" -and $_.CommandLine -like "*<service>*start.cmd*"
}
foreach ($p in @($targets) + @($watch)) { Stop-Process -Id $p.ProcessId -Force }
```

## 7. 端口被占用

```powershell
Get-NetTCPConnection -State Listen -LocalPort <port> | Select-Object OwningProcess
Get-Process -Id <pid>
```

要么停掉旧实例，要么换端口（预览页、服务端、自启脚本三处同步改）。

## 8. 编码与行尾

- `.ps1` 必须是纯 ASCII（PowerShell 5.1 按 ANSI 读取无 BOM 文件，中文会解析失败）。
- `.cmd` 用 CRLF；LF-only 在部分 `goto`/标签场景会出问题。
- `.json` / `.md` 用 UTF-8（无 BOM）。

## 9. 快速自检脚本

```powershell
$port = 8770
$c = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
if ($c) { "port $port listening (PID $($c[0].OwningProcess))" } else { "port $port NOT listening" }
curl.exe -s "http://127.0.0.1:$port/api/health"
```
