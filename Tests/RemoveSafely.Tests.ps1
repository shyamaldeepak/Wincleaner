BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\WinClean.psd1') -Force
    $script:TestRoot = Join-Path $env:TEMP ("winclean-tests-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
}

AfterAll {
    Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Remove-WinCleanItem' {
    # These two integration-level checks need a real C:\Windows and a real
    # Recycle Bin, neither of which exist off Windows. The underlying logic
    # they exercise (protected-path rejection, Recycle Bin routing) is
    # covered platform-independently in Safety.Tests.ps1 and by the
    # fail-closed assertion below; these are skipped rather than deleted so
    # they still run for real on Windows CI/hardware.
    It 'refuses to delete a protected path' -Skip:(-not $IsWindows) {
        $result = Remove-WinCleanItem -Path 'C:\Windows' -Confirm:$false -ErrorAction SilentlyContinue
        $result | Should -BeFalse
        Test-Path -LiteralPath 'C:\Windows' | Should -BeTrue
    }

    It 'no-ops silently on a path that does not exist' {
        $missing = Join-Path $script:TestRoot 'does-not-exist.txt'
        Remove-WinCleanItem -Path $missing -Confirm:$false | Should -BeTrue
    }

    It 'does not delete anything under -WhatIf' {
        $file = Join-Path $script:TestRoot 'whatif-test.txt'
        Set-Content -LiteralPath $file -Value 'hello'
        Remove-WinCleanItem -Path $file -WhatIf
        Test-Path -LiteralPath $file | Should -BeTrue
        Remove-Item -LiteralPath $file -Force
    }

    It 'moves a real file to the Recycle Bin by default' -Skip:(-not $IsWindows) {
        $file = Join-Path $script:TestRoot 'recycle-test.txt'
        Set-Content -LiteralPath $file -Value 'hello'
        Remove-WinCleanItem -Path $file -Confirm:$false | Should -BeTrue
        Test-Path -LiteralPath $file | Should -BeFalse
    }

    It 'fails closed (never permanently deletes) when the Recycle Bin is unavailable' {
        # On this non-Windows test host, Microsoft.VisualBasic's Recycle Bin
        # API throws — Remove-WinCleanItem must report failure and leave the
        # file in place rather than silently falling back to a permanent
        # delete. This is the actual contract under test; on Windows this
        # scenario doesn't naturally occur, so it's the mirror image of the
        # "moves to Recycle Bin" test above.
        if ($IsWindows) { Set-ItResult -Skipped -Because 'Recycle Bin is available on Windows; see the positive test above.'; return }
        $file = Join-Path $script:TestRoot 'fail-closed-test.txt'
        Set-Content -LiteralPath $file -Value 'hello'
        Remove-WinCleanItem -Path $file -Confirm:$false -ErrorAction SilentlyContinue | Should -BeFalse
        Test-Path -LiteralPath $file | Should -BeTrue
        Remove-Item -LiteralPath $file -Force
    }

    It 'permanently deletes only when -Permanent is passed' {
        $file = Join-Path $script:TestRoot 'permanent-test.txt'
        Set-Content -LiteralPath $file -Value 'hello'
        Remove-WinCleanItem -Path $file -Permanent -Confirm:$false | Should -BeTrue
        Test-Path -LiteralPath $file | Should -BeFalse
    }
}
