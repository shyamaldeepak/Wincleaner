BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\WinClean.psd1') -Force
}

Describe 'Win Clean Safety Core' {
    Context 'Protected path detection' {
        It 'protects C:\Windows' {
            Test-WinCleanProtectedPath -Path 'C:\Windows' | Should -BeTrue
        }
        It 'protects C:\Windows\System32 as a subtree' {
            Test-WinCleanProtectedPath -Path 'C:\Windows\System32\drivers' | Should -BeTrue
        }
        It 'protects the bare drive root' {
            Test-WinCleanProtectedPath -Path 'C:\' | Should -BeTrue
        }
        It 'protects a bare user home root' {
            Test-WinCleanProtectedPath -Path 'C:\Users\someone' | Should -BeTrue
        }
        It 'does not protect a normal file inside a user profile' {
            Test-WinCleanProtectedPath -Path 'C:\Users\someone\Downloads\file.txt' | Should -BeFalse
        }
        It 'does not protect ProgramData subfolders (only the bare root is protected)' {
            Test-WinCleanProtectedPath -Path 'C:\ProgramData\SomeVendor\Cache' | Should -BeFalse
        }
        It 'protects bare ProgramData' {
            Test-WinCleanProtectedPath -Path 'C:\ProgramData' | Should -BeTrue
        }
        It 'protects Program Files as a subtree' {
            Test-WinCleanProtectedPath -Path 'C:\Program Files\SomeApp\bin' | Should -BeTrue
        }
    }

    Context 'Path validation gate' {
        It 'rejects relative paths' {
            (Test-WinCleanPathSafeToDelete -Path 'relative\path').IsSafe | Should -BeFalse
        }
        It 'rejects path traversal' {
            (Test-WinCleanPathSafeToDelete -Path 'C:\Users\someone\..\..\Windows').IsSafe | Should -BeFalse
        }
        It 'rejects control characters' {
            $bad = "C:\Users\someone\bad$([char]0)name"
            (Test-WinCleanPathSafeToDelete -Path $bad).IsSafe | Should -BeFalse
        }
        It 'rejects protected roots even when they exist' {
            (Test-WinCleanPathSafeToDelete -Path 'C:\Windows').IsSafe | Should -BeFalse
        }
        It 'accepts a plausible safe temp path' {
            $candidate = Join-Path $env:TEMP 'winclean-safety-test.tmp'
            (Test-WinCleanPathSafeToDelete -Path $candidate).IsSafe | Should -BeTrue
        }
        It 'rejects an empty path' {
            (Test-WinCleanPathSafeToDelete -Path '').IsSafe | Should -BeFalse
        }
    }
}
