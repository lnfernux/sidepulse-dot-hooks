BeforeAll {
    $script:Hook = Join-Path $PSScriptRoot '..\Set-DotState.ps1'

    function Invoke-TestDotState {
        param([string]$State, [string]$SessionId)
        & $script:Hook -State $State -SessionId $SessionId -StateDir $script:StateDir -LedPath $script:Led
    }

    function Get-TestDotColour {
        $text = [IO.File]::ReadAllText($script:Led)
        switch -Regex ($text) {
            '#ff8000' { return 'waiting' }
            '#0040ff' { return 'working' }
            '#00ff00' { return 'done' }
            '^off' { return 'off' }
            default { return 'unknown' }
        }
    }
}

Describe 'Set-DotState' {
    BeforeEach {
        $script:StateDir = Join-Path $TestDrive ([guid]::NewGuid())
        $script:Led = Join-Path $TestDrive "$([guid]::NewGuid()).LED"
        Set-Content -LiteralPath $script:Led -Value 'off' -NoNewline
    }

    It 'keeps the light on working while another session is done' {
        Invoke-TestDotState working a
        Invoke-TestDotState done b
        Get-TestDotColour | Should -Be 'working'
    }

    It 'shows waiting above working and done' {
        Invoke-TestDotState working a
        Invoke-TestDotState waiting b
        Invoke-TestDotState done c
        Get-TestDotColour | Should -Be 'waiting'
    }

    It 'shows done once every session is done' {
        Invoke-TestDotState working a
        Invoke-TestDotState done b
        Invoke-TestDotState done a
        Get-TestDotColour | Should -Be 'done'
    }

    It 'turns off when the last session closes' {
        Invoke-TestDotState working a
        Invoke-TestDotState closed a
        Get-TestDotColour | Should -Be 'off'
    }

    It 'ignores a working session that went stale' {
        Invoke-TestDotState working a
        (Get-Item (Join-Path $script:StateDir 'a.state')).LastWriteTime = (Get-Date).AddMinutes(-31)
        Invoke-TestDotState done b
        Get-TestDotColour | Should -Be 'done'
    }

    It 'always writes exactly 64 bytes' {
        Invoke-TestDotState waiting a
        Invoke-TestDotState closed a
        (Get-Item -LiteralPath $script:Led).Length | Should -Be 64
    }

    It 'keeps an unsafe session id inside the state folder' {
        Invoke-TestDotState working '..\..\escape'
        (Get-ChildItem -LiteralPath $script:StateDir -Filter '*.state').Name | Should -Be 'unknown.state'
    }

    It 'does nothing when the Dot is not mounted' {
        Remove-Item -LiteralPath $script:Led
        Invoke-TestDotState working a
        Test-Path -LiteralPath $script:StateDir | Should -BeFalse
    }
}
