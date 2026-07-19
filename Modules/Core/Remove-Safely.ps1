# Remove-Safely.ps1 — the single choke point every command must use to
# delete anything. Never call Remove-Item directly outside this file.
#
# Contract (mirrors Mole's mole_delete):
#   - Recycle Bin by default. A failed Recycle Bin move fails CLOSED — it
#     never silently falls back to a permanent delete. Only -Permanent
#     performs a real, unrecoverable delete.
#   - Every path goes through Test-WinCleanPathSafeToDelete first. A
#     rejection is logged and the function returns $false; it never throws
#     past the caller for a rejected path, so a batch operation can keep
#     going and report what was skipped.
#   - -WhatIf / -Confirm work natively via SupportsShouldProcess instead of
#     a bespoke dry-run flag.

Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

function Get-WinCleanItemSize {
    param([Parameter(Mandatory)][string]$Path)
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            return (Get-Item -LiteralPath $Path -Force).Length
        }
        if (Test-Path -LiteralPath $Path -PathType Container) {
            $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer } |
                Measure-Object -Property Length -Sum).Sum
            if ($null -eq $sum) { return 0 }
            return [long]$sum
        }
    } catch {
        return $null
    }
    return $null
}

function Remove-WinCleanItem {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][AllowEmptyString()][string]$Path,
        [switch]$Permanent
    )

    process {
        if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
            # Matches Mole's mole_delete: a missing path is a silent no-op,
            # not an error — the desired end state (path is gone) already holds.
            return $true
        }

        $check = Test-WinCleanPathSafeToDelete -Path $Path
        if (-not $check.IsSafe) {
            Write-WinCleanLog -Action 'delete' -Status 'rejected' -Path $Path -Detail $check.Reason
            Write-Error "Win Clean refused to delete '$Path': $($check.Reason)"
            return $false
        }

        $size = Get-WinCleanItemSize -Path $Path
        $verb = if ($Permanent) { 'Permanently delete' } else { 'Move to Recycle Bin' }

        if (-not $PSCmdlet.ShouldProcess($Path, $verb)) {
            Write-WinCleanLog -Action 'delete' -Status 'dry-run' -Path $Path -SizeBytes $size
            return $true
        }

        $isDir = Test-Path -LiteralPath $Path -PathType Container

        if ($Permanent) {
            try {
                Remove-Item -LiteralPath $Path -Recurse:$isDir -Force -ErrorAction Stop
                Write-WinCleanLog -Action 'delete-permanent' -Status 'ok' -Path $Path -SizeBytes $size
                return $true
            } catch {
                Write-WinCleanLog -Action 'delete-permanent' -Status 'error' -Path $Path -SizeBytes $size -Detail $_.Exception.Message
                Write-Error "Win Clean failed to permanently delete '$Path': $($_.Exception.Message)"
                return $false
            }
        }

        try {
            $ui = [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs
            $recycle = [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            if ($isDir) {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($Path, $ui, $recycle)
            } else {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Path, $ui, $recycle)
            }
            Write-WinCleanLog -Action 'delete-trash' -Status 'ok' -Path $Path -SizeBytes $size
            return $true
        } catch {
            # Fail closed: never fall back to a permanent delete just because
            # the Recycle Bin move failed.
            Write-WinCleanLog -Action 'delete-trash' -Status 'trash-failed' -Path $Path -SizeBytes $size -Detail $_.Exception.Message
            Write-Error "Win Clean: Recycle Bin unavailable for '$Path' ($($_.Exception.Message)). Refusing permanent delete — pass -Permanent to delete immediately."
            return $false
        }
    }
}
