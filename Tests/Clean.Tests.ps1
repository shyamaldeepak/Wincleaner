BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\WinClean.psd1') -Force
}

Describe 'Get-WinCleanRecycleBinPreview' {
    It 'never throws and reports Available:$false where the Shell COM object is unavailable' {
        { Get-WinCleanRecycleBinPreview } | Should -Not -Throw
        if (-not $IsWindows) {
            (Get-WinCleanRecycleBinPreview).Available | Should -BeFalse
        }
    }
}

Describe 'Clear-WinCleanRecycleBin' {
    It 'never throws and returns $false when Clear-RecycleBin is unavailable' -Skip:$IsWindows {
        Clear-WinCleanRecycleBin -Confirm:$false -ErrorAction SilentlyContinue | Should -BeFalse
    }
    It 'does nothing under -WhatIf' {
        { Clear-WinCleanRecycleBin -WhatIf } | Should -Not -Throw
    }
}

Describe 'Get-WinCleanCleanPreview' {
    It 'never includes the Recycle Bin entry without -IncludeDisabled' {
        $preview = @(Get-WinCleanCleanPreview)
        ($preview | Where-Object { $_.Name -eq 'Recycle Bin' }).Count | Should -Be 0
    }
    It 'includes a disabled Recycle Bin entry with -IncludeDisabled only where the Shell COM object is available' -Skip:(-not $IsWindows) {
        $preview = @(Get-WinCleanCleanPreview -IncludeDisabled)
        $binEntry = $preview | Where-Object { $_.Name -eq 'Recycle Bin' }
        $binEntry.Count | Should -Be 1
        $binEntry.Enabled | Should -BeFalse
    }
}

Describe 'Invoke-WinCleanClean' {
    It 'does not throw producing a JSON preview' {
        { Invoke-WinCleanClean -Json } | Should -Not -Throw
    }
}
