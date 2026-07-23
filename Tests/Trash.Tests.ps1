BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\WinClean.psd1') -Force
}

Describe 'Get-WinCleanRecycleBinStatus' {
    It 'queries Recycle Bin status without throwing' {
        { Get-WinCleanRecycleBinStatus } | Should -Not -Throw
        $status = Get-WinCleanRecycleBinStatus
        $status | Should -Not -BeNullOrEmpty
        $status.Count | Should -BeGreaterOrEqual 0
        $status.SizeBytes | Should -BeGreaterOrEqual 0
    }
}

Describe 'Invoke-WinCleanTrash' {
    It 'runs trash status command without throwing' {
        { Invoke-WinCleanTrash -Json } | Should -Not -Throw
    }
}
