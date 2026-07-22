BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\WinClean.psd1') -Force
}

Describe 'Invoke-WinCleanMenu' {
    It 'does not throw when exported function is loaded' {
        Get-Command Invoke-WinCleanMenu | Should -Not -BeNullOrEmpty
    }
}
