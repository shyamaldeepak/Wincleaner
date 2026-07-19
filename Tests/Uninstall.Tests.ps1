BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\WinClean.psd1') -Force
}

Describe 'Uninstall inventory' {
    It 'returns installed apps without throwing' {
        { Get-WinCleanInstalledApps } | Should -Not -Throw
    }

    It 'filters by name substring' {
        $all = Get-WinCleanInstalledApps
        if ($all.Count -gt 0) {
            $needle = $all[0].Name.Substring(0, [Math]::Min(3, $all[0].Name.Length))
            $filtered = Get-WinCleanInstalledApps -Filter $needle
            $filtered.Count | Should -BeGreaterThan 0
        }
    }

    It 'excludes Appx frameworks and resource packages' {
        $appx = Get-WinCleanAppxApps
        ($appx | Where-Object { $_.Name -match 'Framework' }).Count | Should -Be 0
    }

    It 'never fabricates an uninstall command for an app that has none' {
        $fake = [PSCustomObject]@{
            Source = 'Registry'; Name = 'FakeApp'; UninstallString = $null
            QuietUninstall = $null; InstallLocation = $null; PackageFullName = $null
        }
        Uninstall-WinCleanApp -App $fake -Confirm:$false -ErrorAction SilentlyContinue | Should -BeFalse
    }

    It 'produces a JSON array — not the bare string "null" — when -Filter matches nothing' {
        # Regression test: piping an empty array into ConvertTo-Json (or
        # assigning a function's empty result to a caller variable without
        # wrapping it in @()) silently degrades to no output or the literal
        # string "null" instead of "[]" — see Invoke-WinCleanUninstall and
        # Get-WinCleanInstalledApps for the fix. A filter guaranteed not to
        # match anything on this test host proves the -Json path degrades
        # correctly to an empty JSON array either way.
        $json = Invoke-WinCleanUninstall -Filter 'winclean-guaranteed-no-match-zzz' -Json | Out-String
        $json.Trim() | Should -Not -Be 'null'
        $json.Trim() | Should -Be '[]'
    }
}
