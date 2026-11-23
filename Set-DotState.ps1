[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('working', 'waiting', 'done', 'closed')]
    [string]$State,

    [string]$SessionId,

    [string]$StateDir = (Join-Path $env:LOCALAPPDATA 'sidepulse-dot'),

    [string]$LedPath = 'D:\LEDS.LED',

    # shortcut: a working session silent for longer is treated as dead, raise if single tool calls run longer
    [int]$WorkingTtlMinutes = 30,

    [int]$IdleTtlHours = 12
)

if (-not (Test-Path -LiteralPath $LedPath)) { return }

if (-not $SessionId -and [Console]::IsInputRedirected) {
    try {
        $hookInput = [Console]::In.ReadToEnd() | ConvertFrom-Json
        # Claude Code sends session_id, Copilot's camelCase events send sessionId
        $SessionId = if ($hookInput.session_id) { $hookInput.session_id } else { $hookInput.sessionId }
        $hookEvent = $hookInput.hook_event_name
    } catch {
        $SessionId = $null
    }
}
# the id becomes a file name, so anything outside this set shares one slot
if ($SessionId -notmatch '^[A-Za-z0-9_-]{1,100}$') { $SessionId = 'unknown' }

$programs = @{
    waiting = "brightness 80`n#ff8000 0.8s pulse`nrepeat`n;"
    working = "brightness 60`n#0040ff 0.5s ease`n;"
    done    = "brightness 60`n#00ff00 0.4s ease`n;"
    off     = "off`n;"
}

$mutex = [Threading.Mutex]::new($false, 'SidePulseDotState')
$held = $false
$logFile = Join-Path $StateDir 'dot.log'
$logPrefix = '{0:s} {1} {2} {3}' -f (Get-Date), $SessionId, $hookEvent, $State
try {
    try { $held = $mutex.WaitOne(3000) } catch [Threading.AbandonedMutexException] { $held = $true }

    $null = New-Item -ItemType Directory -Path $StateDir -Force
    $stateFile = Join-Path $StateDir "$SessionId.state"
    if ($State -eq 'closed') {
        Remove-Item -LiteralPath $stateFile -ErrorAction SilentlyContinue
    } else {
        Set-Content -LiteralPath $stateFile -Value $State -NoNewline
    }

    $now = Get-Date
    $live = foreach ($file in Get-ChildItem -LiteralPath $StateDir -Filter '*.state') {
        $sessionState = Get-Content -LiteralPath $file.FullName -Raw
        $ttl = if ($sessionState -eq 'working') { [timespan]::FromMinutes($WorkingTtlMinutes) } else { [timespan]::FromHours($IdleTtlHours) }
        if (($now - $file.LastWriteTime) -gt $ttl) {
            Remove-Item -LiteralPath $file.FullName -ErrorAction SilentlyContinue
            continue
        }
        $sessionState
    }

    $show = 'waiting', 'working', 'done' | Where-Object { $live -contains $_ } | Select-Object -First 1
    if (-not $show) { $show = 'off' }

    # fixed 64-byte in-place write: the Dot parses a truncated or shorter file as an error
    $bytes = [Text.Encoding]::ASCII.GetBytes($programs[$show].PadRight(64, '-'))
    $stream = [IO.File]::OpenWrite($LedPath)
    try {
        # after a single write the Dot keeps showing the previous program, so write twice and flush each to the device
        foreach ($pass in 1, 2) {
            $stream.Position = 0
            $stream.Write($bytes, 0, 64)
            $stream.Flush($true)
        }
    } finally { $stream.Dispose() }

    # shortcut: the log is dropped whole at 1 MB, rotate it if history across that point matters
    if ((Get-Item -LiteralPath $logFile -ErrorAction Ignore).Length -gt 1MB) { Remove-Item -LiteralPath $logFile }
    Add-Content -LiteralPath $logFile -Value "$logPrefix held=$held live=$($live -join ',') show=$show"
} catch {
    Write-Verbose "Dot update failed: $_"
    Add-Content -LiteralPath $logFile -Value "$logPrefix failed: $_" -ErrorAction SilentlyContinue
} finally {
    if ($held) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
