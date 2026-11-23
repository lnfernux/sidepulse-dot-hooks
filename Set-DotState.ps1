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
    try { $stream.Write($bytes, 0, 64) } finally { $stream.Dispose() }
} catch {
    Write-Verbose "Dot update failed: $_"
} finally {
    if ($held) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
