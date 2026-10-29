# cdp.ps1 - minimal Chrome DevTools Protocol client over WebSocket.
#
# Why this exists: the browser plugin only drives its own instance and exposes no
# "connect to an external endpoint" tool, and Code Mode has no WebSocket. So the
# only way to drive an Edge profile that is already logged in is to speak CDP
# ourselves. PowerShell 5.1 ships System.Net.WebSockets.ClientWebSocket, which is
# enough.
#
# One operation per invocation: each run opens a socket, does its thing, closes.
# That keeps every script simple and survives a wedged connection. Pass -TargetId
# when the operation must apply to a specific tab.
#
# ASCII-only: PowerShell 5.1 reads BOM-less .ps1 as ANSI/GBK, so -EvalJS carrying
# Chinese must come from a file (-EvalFile), never inline.
param(
  [int]$Port = 9222,
  [ValidateSet("List", "Open", "Eval", "Shot", "Close", "Activate", "Version",
               "Type", "Key", "WaitFor", "Click", "Nav", "NewChat")]
  [string]$Op = "List",
  [string]$Url = "",
  [string]$EvalJS = "",
  [string]$EvalFile = "",
  [string]$TextFile = "",       # text to type, UTF-8
  [string]$Key = "",            # Key: Enter | Tab | Escape
  [int]$ClickX = 0,
  [int]$ClickY = 0,
  [string]$OutPath = "",
  [string]$TargetId = "",
  [int]$Width = 0,
  [int]$Height = 0,
  [int]$TimeoutSec = 60
)
$ErrorActionPreference = "Stop"
$base = "http://127.0.0.1:$Port"

function Get-Targets {
  # A bare "无法连接到远程服务器" here means the browser instance is gone, and
  # nothing in the message says how to get it back. The CDP Edge has to be
  # started by hand with --remote-debugging-port, and it needs its own profile
  # (Edge refuses the debug port under the default one) - so spell out the exact
  # command instead of letting every batch die with a WebException.
  try {
    $r = Invoke-RestMethod -Uri "$base/json/list" -TimeoutSec 10
  } catch {
    throw ("No CDP browser on port {0}. Start one first:" -f $Port) + "`n" +
          ("  & 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' `"--remote-debugging-port={0}`" `"--user-data-dir=D:\文字\temp\edge_cdp_profile`" https://www.doubao.com/chat/" -f $Port) + "`n" +
          "  (log into doubao once in that window; the profile keeps the session)"
  }
  return @($r | Where-Object { $_.type -eq "page" })
}

# PowerShell 5.1 has no ConvertFrom-Json -Depth, and no -AsHashtable; wrap the
# standard call so callers do not have to remember the ordering rules.
function Send-Cdp([string]$wsUrl, [string]$method, [hashtable]$params, [int]$timeoutSec) {
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $cts = New-Object System.Threading.CancellationTokenSource
  $cts.CancelAfter($timeoutSec * 1000)
  try {
    $ws.ConnectAsync([Uri]$wsUrl, $cts.Token).Wait()
  } catch {
    throw ("connect failed: " + $_.Exception.Message)
  }

  $id = 1
  $msg = @{ id = $id; method = $method; params = $params } | ConvertTo-Json -Depth 8 -Compress
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
  $seg = New-Object System.ArraySegment[byte] (,$bytes)
  $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()

  # Read until we see the response frame carrying our id. Events (Page.loadFired
  # and friends) interleave with it and must be skipped, and CDP frames arrive
  # fragmented, so accumulate until EndOfMessage.
  $buf = New-Object byte[] 1048576
  while ($true) {
    $acc = New-Object System.Text.StringBuilder
    do {
      $rseg = New-Object System.ArraySegment[byte] (,$buf)
      $res = $ws.ReceiveAsync($rseg, $cts.Token).GetAwaiter().GetResult()
      if ($res.Count -gt 0) { [void]$acc.Append([System.Text.Encoding]::UTF8.GetString($buf, 0, $res.Count)) }
    } while (-not $res.EndOfMessage)
    $txt = $acc.ToString()
    if ([string]::IsNullOrWhiteSpace($txt)) { continue }
    try { $obj = $txt | ConvertFrom-Json } catch { continue }
    if ($obj.PSObject.Properties.Name -contains "id" -and $obj.id -eq $id) {
      $ws.Dispose()
      return $obj
    }
  }
}

function Pick-Target([string]$id) {
  $ts = Get-Targets
  if ($ts.Count -eq 0) { throw "no page targets on port $Port" }
  if ($id -ne "") {
    $t = $ts | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if (-not $t) { throw "target $id not found" }
    return $t
  }
  return $ts[0]
}

switch ($Op) {
  "Version" {
    (Invoke-RestMethod -Uri "$base/json/version" -TimeoutSec 10) | ConvertTo-Json -Depth 4
  }
  "List" {
    Get-Targets | ForEach-Object { "{0}`t{1}`t{2}" -f $_.id, $_.title, $_.url }
  }
  "Open" {
    if ($Url -eq "") { throw "-Url required" }
    # Newer builds require PUT on /json/new
    $t = $null
    try { $t = Invoke-RestMethod -Method Put -Uri ("$base/json/new?" + [uri]::EscapeDataString($Url)) -TimeoutSec 15 }
    catch { $t = Invoke-RestMethod -Method Get -Uri ("$base/json/new?" + [uri]::EscapeDataString($Url)) -TimeoutSec 15 }
    "opened`t{0}`t{1}" -f $t.id, $t.url
  }
  "Close" {
    $t = Pick-Target $TargetId
    Invoke-RestMethod -Uri ("$base/json/close/" + $t.id) -TimeoutSec 10 | Out-Null
    "closed`t" + $t.id
  }
  "Activate" {
    $t = Pick-Target $TargetId
    Invoke-RestMethod -Uri ("$base/json/activate/" + $t.id) -TimeoutSec 10 | Out-Null
    "activated`t" + $t.id
  }
  "Eval" {
    $js = if ($EvalFile -ne "") { [System.IO.File]::ReadAllText($EvalFile, [System.Text.Encoding]::UTF8) } else { $EvalJS }
    if ([string]::IsNullOrWhiteSpace($js)) { throw "-EvalJS or -EvalFile required" }
    $t = Pick-Target $TargetId
    $r = Send-Cdp $t.webSocketDebuggerUrl "Runtime.evaluate" @{
      expression = $js; returnByValue = $true; awaitPromise = $true
    } $TimeoutSec
    if ($r.result -and $r.result.exceptionDetails) {
      Write-Error ("eval threw: " + ($r.result.exceptionDetails | ConvertTo-Json -Depth 6 -Compress))
    }
    $v = $r.result.result.value
    if ($v -is [string]) { $v } else { ($v | ConvertTo-Json -Depth 8 -Compress) }
  }
  # Input.insertText drops text into whatever has focus, so the composer must be
  # focused first. Dispatching a real key per character would be far slower and
  # would trigger each site's own autocomplete handlers.
  "Type" {
    if ($TextFile -eq "") { throw "-TextFile required" }
    $t = Pick-Target $TargetId
    $txt = [System.IO.File]::ReadAllText($TextFile, [System.Text.Encoding]::UTF8)
    [void](Send-Cdp $t.webSocketDebuggerUrl "Runtime.evaluate" @{
      expression = "(function(){var e=document.querySelector('textarea,[contenteditable=""true""]');if(e){e.focus();return 'ok';}return 'no-input';})()"
      returnByValue = $true
    } $TimeoutSec)
    $r = Send-Cdp $t.webSocketDebuggerUrl "Input.insertText" @{ text = $txt } $TimeoutSec
    "typed`t{0} chars" -f $txt.Length
  }
  "Key" {
    if ($Key -eq "") { throw "-Key required" }
    $t = Pick-Target $TargetId
    $codes = @{
      "Enter"   = @{ windowsVirtualKeyCode = 13; key = "Enter"; code = "Enter"; text = "`r" }
      "Tab"     = @{ windowsVirtualKeyCode = 9;  key = "Tab";   code = "Tab" }
      "Escape"  = @{ windowsVirtualKeyCode = 27; key = "Escape"; code = "Escape" }
    }
    if (-not $codes.ContainsKey($Key)) { throw "unsupported key: $Key" }
    $c = $codes[$Key]
    $base = @{ type = "keyDown"; key = $c.key; code = $c.code; windowsVirtualKeyCode = $c.windowsVirtualKeyCode; nativeVirtualKeyCode = $c.windowsVirtualKeyCode }
    if ($c.ContainsKey("text")) { $base["text"] = $c.text }
    [void](Send-Cdp $t.webSocketDebuggerUrl "Input.dispatchKeyEvent" $base $TimeoutSec)
    [void](Send-Cdp $t.webSocketDebuggerUrl "Input.dispatchKeyEvent" @{ type = "keyUp"; key = $c.key; code = $c.code; windowsVirtualKeyCode = $c.windowsVirtualKeyCode; nativeVirtualKeyCode = $c.windowsVirtualKeyCode } $TimeoutSec)
    "key`t$Key"
  }
  # Start a genuinely new conversation. Neither location.href nor Page.navigate
  # does this: both land on an EXISTING thread, so the next prompt gets appended
  # to someone else's conversation and extraction - which reads the first user
  # message - reports the wrong monster. The sidebar control carries a stable
  # data-testid, so target that and dispatch real mouse events (the SPA ignores
  # synthetic .click()).
  "NewChat" {
    $t = Pick-Target $TargetId
    $expr = @'
(function(){
  // doubao has shipped two different composers. The personal build exposes
  // [data-testid="create_conversation_button"]; the work/org build exposes
  // create_office_task_button instead. Try both so the batch keeps working when
  // the account switches.
  var el = document.querySelector('[data-testid="create_conversation_button"]')
        || document.querySelector('[data-testid="create_office_task_button"]');
  if(!el) return null;
  var r = el.getBoundingClientRect();
  return { x: r.left + r.width/2, y: r.top + r.height/2, url: location.href };
})()
'@
    $prev = ""
    $res = Send-Cdp $t.webSocketDebuggerUrl "Runtime.evaluate" @{ expression = $expr; returnByValue = $true } 20
    if ($res.result -and $res.result.result -and $res.result.result.value) {
      $v = $res.result.result.value
      $prev = [string]$v.url
      foreach ($ty in @("mouseMoved", "mousePressed", "mouseReleased")) {
        $args = @{ type = $ty; x = [double]$v.x; y = [double]$v.y; button = "left"; clickCount = 1 }
        [void](Send-Cdp $t.webSocketDebuggerUrl "Input.dispatchMouseEvent" $args 20)
      }
    }
    $want = ""
    if ($prev -match '/chat/([A-Za-z0-9_]+)') { $want = $Matches[1] }
    $dl = [DateTime]::UtcNow.AddSeconds(45)
    while ([DateTime]::UtcNow -lt $dl) {
      Start-Sleep -Milliseconds 800
      $c = Send-Cdp $t.webSocketDebuggerUrl "Runtime.evaluate" @{ expression = "location.href"; returnByValue = $true } 15
      if ($c.result -and $c.result.result -and $c.result.result.value) {
        $u = [string]$c.result.result.value
        if ($u -match '/chat/([A-Za-z0-9_]+)') {
          $now = $Matches[1]
          if ($u -ne $prev) { "newchat`t$now"; return }
        } else { "newchat`t(no id yet: $u)"; return }
      }
    }
    "newchat`tTIMEOUT url=$prev"
  }
  "Click" {
    $t = Pick-Target $TargetId
    $p = @{ type = "mousePressed"; x = $ClickX; y = $ClickY; button = "left"; clickCount = 1 }
    $r = Send-Cdp $t.webSocketDebuggerUrl "Input.dispatchMouseEvent" $p $TimeoutSec
    $p2 = @{ type = "mouseReleased"; x = $ClickX; y = $ClickY; button = "left"; clickCount = 1 }
    [void](Send-Cdp $t.webSocketDebuggerUrl "Input.dispatchMouseEvent" $p2 $TimeoutSec)
    "click`t{0},{1}" -f $ClickX, $ClickY
  }
  # Poll an expression until it is truthy. doubao renders results asynchronously,
  # so "did the image appear yet" cannot be a single eval.
  "WaitFor" {
    if ($EvalJS -eq "") { throw "-EvalJS required" }
    $t = Pick-Target $TargetId
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSec)
    while ([DateTime]::UtcNow -lt $deadline) {
      $r = Send-Cdp $t.webSocketDebuggerUrl "Runtime.evaluate" @{
        expression = $EvalJS; returnByValue = $true
      } 15
      if ($r.result -and $r.result.result -and $r.result.result.value) {
        "true"
        return
      }
      Start-Sleep -Seconds 2
    }
    "false"
  }
  # A real protocol-level navigation. Setting location.href to the same SPA route
  # is a no-op in doubao: the chat stayed on yesterday's thread, so "focus the
  # last textarea, type, Enter" typed into the WRONG conversation and the
  # prompts never reached a new thread at all.
  "Nav" {
    if ($Url -eq "") { throw "-Url required" }
    $t = Pick-Target $TargetId
    [void](Send-Cdp $t.webSocketDebuggerUrl "Page.navigate" @{ url = $Url } $TimeoutSec)
    "nav`t$Url"
  }
  "Shot" {
    if ($OutPath -eq "") { throw "-OutPath required" }
    $t = Pick-Target $TargetId
    if ($Width -gt 0 -and $Height -gt 0) {
      [void](Send-Cdp $t.webSocketDebuggerUrl "Emulation.setDeviceMetricsOverride" @{
        width = $Width; height = $Height; deviceScaleFactor = 1; mobile = $false
      } $TimeoutSec)
    }
    $r = Send-Cdp $t.webSocketDebuggerUrl "Page.captureScreenshot" @{ format = "png" } $TimeoutSec
    [System.IO.File]::WriteAllBytes($OutPath, [Convert]::FromBase64String($r.result.data))
    "shot`t{0}" -f $OutPath
  }
}
