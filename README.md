# sidepulse-dot-hooks

Hooks that show the state of Claude Code and GitHub Copilot sessions on a [SidePulse Dot](https://github.com/inteliwear/sidepulse) under Windows. One PowerShell script writes to the Dot's `LEDS.LED` file, and no vendor software is installed.

## States

| Light | Meaning |
| --- | --- |
| Amber pulse | A session waits for a permission or an answer |
| Blue | A session is working |
| Green | Every session has finished its turn |
| Off | No session is open |

With several sessions open, the light shows the most urgent state among them.

## Requirements

- Windows with PowerShell 7 at `C:\Program Files\PowerShell\7\pwsh.exe`
- A SidePulse Dot mounted as a drive, run here on firmware 1.1.14
- Claude Code, GitHub Copilot, or both

## Setup

1. Copy `Set-DotState.ps1` to `%USERPROFILE%\.claude\hooks\sidepulse\`.
2. Check the Dot's drive letter in Explorer. The script assumes `D:`. For another letter, change the `$LedPath` default at the top of the script.
3. For Claude Code, merge the `hooks` object from `examples/claude-settings.json` into `%USERPROFILE%\.claude\settings.json`. Where an event already has hooks, append the entry to that event's array.
4. For Copilot, copy `examples/copilot-hooks.json` to `%USERPROFILE%\.copilot\hooks\sidepulse-dot.json`.
5. Replace `<you>` with your Windows user name in every file you copied.
6. Restart open sessions so they load the new hooks.

The Claude Code hooks cover the terminal, the VS Code extension and the Code tab in Claude Desktop, because all three read the same settings file.

## Check

Run the script by hand with a made-up session id. The first command turns the light amber and the second clears that session again.

```powershell
pwsh -File $env:USERPROFILE\.claude\hooks\sidepulse\Set-DotState.ps1 -State waiting -SessionId test
pwsh -File $env:USERPROFILE\.claude\hooks\sidepulse\Set-DotState.ps1 -State closed -SessionId test
```

## Behaviour

- Each session's state is a file in `%LOCALAPPDATA%\sidepulse-dot`, named after the session id from the hook input.
- A working state expires after 30 minutes without a tool call, so a crashed session can't hold the light blue. `-WorkingTtlMinutes` changes that.
- Waiting and done states expire after 12 hours. `-IdleTtlHours` changes that.
- Every write is 64 bytes, in place. The Dot blinks red when it reads a half-written or shorter program.
- Each program is written twice and flushed to the device. After a single write the Dot kept showing the previous program until the next write arrived.
- Each call adds a line to `dot.log` in the same folder, with the session, the hook event and the state shown. The log is deleted when it passes 1 MB.
- The script does nothing when the Dot is unplugged.

## Limits

- A single tool call that runs longer than 30 minutes drops its session out of the working state early.
- In VS Code and Claude Desktop, Claude Code raises the waiting state about six seconds after a prompt appears, and skips it when you answer sooner.
- Copilot in VS Code documents no event for the waiting state, so it shows blue and green only.
- The Copilot example follows the [hooks reference](https://docs.github.com/en/copilot/reference/hooks-configuration), where hooks in VS Code are a preview feature.

## Tests

```powershell
Invoke-Pester -Path tests
```
