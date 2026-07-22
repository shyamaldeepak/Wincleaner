BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\WinClean.psd1') -Force
}

Describe 'Get-WinCleanStartupRegistryEntries' {
    It 'never throws, even off Windows where the registry PSDrive does not exist' {
        { Get-WinCleanStartupRegistryEntries } | Should -Not -Throw
    }
}

Describe 'Get-WinCleanStartupFolderEntries' {
    Context 'when the Startup folder exists' {
        BeforeAll {
            $script:OriginalAppData = $env:APPDATA
            $script:TestAppData = Join-Path $env:TEMP ("winclean-startup-" + [guid]::NewGuid())
            $script:StartupDir = Join-Path $script:TestAppData 'Microsoft\Windows\Start Menu\Programs\Startup'
            New-Item -ItemType Directory -Path $script:StartupDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $script:StartupDir 'app.lnk') -Value 'x'
            $env:APPDATA = $script:TestAppData
        }
        AfterAll {
            $env:APPDATA = $script:OriginalAppData
            Remove-Item -LiteralPath $script:TestAppData -Recurse -Force -ErrorAction SilentlyContinue
        }
        It 'finds files in the current-user Startup folder' {
            $entries = @(Get-WinCleanStartupFolderEntries)
            ($entries | Where-Object { $_.Name -eq 'app.lnk' -and $_.Scope -eq 'CurrentUser' }).Count | Should -Be 1
        }
    }

    Context 'when the Startup folder is missing' {
        It 'never throws and returns nothing' {
            $originalAppData = $env:APPDATA
            $originalProgramData = $env:ProgramData
            $env:APPDATA = Join-Path $env:TEMP ('winclean-does-not-exist-' + [guid]::NewGuid())
            $env:ProgramData = Join-Path $env:TEMP ('winclean-does-not-exist-' + [guid]::NewGuid())
            try {
                { Get-WinCleanStartupFolderEntries } | Should -Not -Throw
                @(Get-WinCleanStartupFolderEntries) | Should -BeNullOrEmpty
            } finally {
                $env:APPDATA = $originalAppData
                $env:ProgramData = $originalProgramData
            }
        }
    }
}

Describe 'Invoke-WinCleanStartup' {
    It 'produces valid JSON with -Json' {
        $json = Invoke-WinCleanStartup -Json | Out-String
        { $json | ConvertFrom-Json } | Should -Not -Throw
    }
    It 'does not throw in table output mode' {
        { Invoke-WinCleanStartup } | Should -Not -Throw
    }
}
