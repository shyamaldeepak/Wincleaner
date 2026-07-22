BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\WinClean.psd1') -Force
}

Describe 'Invoke-WinCleanHealth' {
    It 'evaluates health score without throwing' {
        { Get-WinCleanHealthScore } | Should -Not -Throw
        $res = Get-WinCleanHealthScore
        $res.Score | Should -BeGreaterOrEqual 0
        $res.Score | Should -BeLessOrEqual 100
    }
    It 'runs health check command without throwing' {
        { Invoke-WinCleanHealth } | Should -Not -Throw
    }
}
