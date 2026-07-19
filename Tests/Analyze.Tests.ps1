BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\WinClean.psd1') -Force
    $script:TestRoot = Join-Path $env:TEMP ("winclean-analyze-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $script:TestRoot 'small.txt') -Value ('a' * 10) -NoNewline
    Set-Content -LiteralPath (Join-Path $script:TestRoot 'big.txt') -Value ('b' * 1000) -NoNewline
    New-Item -ItemType Directory -Path (Join-Path $script:TestRoot 'subdir') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $script:TestRoot 'subdir\nested.txt') -Value ('c' * 500) -NoNewline
}

AfterAll {
    Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Get-WinCleanChildSizes' {
    It 'sorts children largest to smallest' {
        $items = Get-WinCleanChildSizes -Path $script:TestRoot
        $items[0].Name | Should -Be 'big.txt'
        $items[-1].Name | Should -Be 'small.txt'
    }
    It 'sums directory sizes recursively' {
        $items = Get-WinCleanChildSizes -Path $script:TestRoot
        ($items | Where-Object { $_.Name -eq 'subdir' }).SizeBytes | Should -Be 500
    }
    It 'marks directories with IsDir' {
        $items = Get-WinCleanChildSizes -Path $script:TestRoot
        ($items | Where-Object { $_.Name -eq 'subdir' }).IsDir | Should -BeTrue
        ($items | Where-Object { $_.Name -eq 'big.txt' }).IsDir | Should -BeFalse
    }
}

Describe 'Invoke-WinCleanAnalyze non-interactive path' {
    It 'does not throw on -NonInteractive' {
        { Invoke-WinCleanAnalyze -Path $script:TestRoot -NonInteractive } | Should -Not -Throw
    }
    It 'produces valid JSON with -Json' {
        $json = Invoke-WinCleanAnalyze -Path $script:TestRoot -Json | Out-String
        { $json | ConvertFrom-Json } | Should -Not -Throw
    }
}

Describe 'Get-WinCleanDuplicateFiles' {
    BeforeAll {
        $script:DupRoot = Join-Path $env:TEMP ("winclean-dup-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:DupRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:DupRoot 'a.txt') -Value ('x' * 2000) -NoNewline
        Set-Content -LiteralPath (Join-Path $script:DupRoot 'b.txt') -Value ('x' * 2000) -NoNewline
        Set-Content -LiteralPath (Join-Path $script:DupRoot 'c.txt') -Value ('y' * 2000) -NoNewline
    }
    AfterAll {
        Remove-Item -LiteralPath $script:DupRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    It 'groups files with identical content' {
        $groups = @(Get-WinCleanDuplicateFiles -Path $script:DupRoot -MinSizeBytes 1)
        $groups.Count | Should -Be 1
        $groups[0].Count | Should -Be 2
        $groups[0].Files | Should -Contain (Join-Path $script:DupRoot 'a.txt')
        $groups[0].Files | Should -Contain (Join-Path $script:DupRoot 'b.txt')
    }
    It 'does not group files with different content, even at the same size' {
        $groups = @(Get-WinCleanDuplicateFiles -Path $script:DupRoot -MinSizeBytes 1)
        ($groups[0].Files) -notcontains (Join-Path $script:DupRoot 'c.txt') | Should -BeTrue
    }
    It 'excludes files below MinSizeBytes' {
        $groups = @(Get-WinCleanDuplicateFiles -Path $script:DupRoot -MinSizeBytes 999999)
        $groups.Count | Should -Be 0
    }
    It 'reports WastedBytes as size times (count-1)' {
        $groups = @(Get-WinCleanDuplicateFiles -Path $script:DupRoot -MinSizeBytes 1)
        $groups[0].WastedBytes | Should -Be $groups[0].SizeBytes
    }
}

Describe 'Invoke-WinCleanAnalyze -Duplicates' {
    It 'does not throw with -Duplicates -Json' {
        { Invoke-WinCleanAnalyze -Path $script:TestRoot -Duplicates -Json } | Should -Not -Throw
    }
    It 'produces valid JSON' {
        $json = Invoke-WinCleanAnalyze -Path $script:TestRoot -Duplicates -Json | Out-String
        { $json | ConvertFrom-Json } | Should -Not -Throw
    }
}
