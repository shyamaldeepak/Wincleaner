BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\WinClean.psd1') -Force
    $script:OriginalLocalAppData = $env:LOCALAPPDATA
    $script:TestRoot = Join-Path $env:TEMP ("winclean-history-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
    $env:LOCALAPPDATA = $script:TestRoot

    $logPath = Get-WinCleanLogPath
    $lines = @(
        '{"timestamp":"2026-01-01T00:00:00.0000000Z","action":"delete-trash","status":"ok","path":"C:\\a.txt","sizeBytes":100,"detail":null}'
        '{"timestamp":"2026-01-02T00:00:00.0000000Z","action":"delete","status":"rejected","path":"C:\\Windows","sizeBytes":null,"detail":"protected-path"}'
        '{"timestamp":"2026-01-03T00:00:00.0000000Z","action":"process-close","status":"ok","path":"notepad","sizeBytes":null,"detail":null}'
        'this is not valid json'
    )
    Set-Content -LiteralPath $logPath -Value $lines -Encoding utf8
}

AfterAll {
    $env:LOCALAPPDATA = $script:OriginalLocalAppData
    Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Get-WinCleanHistory' {
    It 'returns all entries newest-first with no filter, skipping the corrupt line' {
        $entries = @(Get-WinCleanHistory)
        $entries.Count | Should -Be 3
        $entries[0].action | Should -Be 'process-close'
        $entries[-1].action | Should -Be 'delete-trash'
    }
    It 'filters by Action' {
        $entries = @(Get-WinCleanHistory -Action 'delete-trash')
        $entries.Count | Should -Be 1
        $entries[0].path | Should -Be 'C:\a.txt'
    }
    It 'filters by Status' {
        $entries = @(Get-WinCleanHistory -Status 'rejected')
        $entries.Count | Should -Be 1
        $entries[0].action | Should -Be 'delete'
    }
    It 'respects -Last' {
        $entries = @(Get-WinCleanHistory -Last 1)
        $entries.Count | Should -Be 1
        $entries[0].action | Should -Be 'process-close'
    }
    It 'returns an empty array when the log file does not exist' {
        $env:LOCALAPPDATA = Join-Path $env:TEMP ("winclean-missing-" + [guid]::NewGuid())
        @(Get-WinCleanHistory) | Should -BeNullOrEmpty
        $env:LOCALAPPDATA = $script:TestRoot
    }
}

Describe 'Invoke-WinCleanHistory' {
    It 'does not throw with no filters' {
        { Invoke-WinCleanHistory } | Should -Not -Throw
    }
    It 'produces valid JSON with -Json' {
        $json = Invoke-WinCleanHistory -Json | Out-String
        { $json | ConvertFrom-Json } | Should -Not -Throw
    }
}
