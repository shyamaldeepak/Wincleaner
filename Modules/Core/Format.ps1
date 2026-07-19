# Format.ps1 — small shared display helpers used by Status/Analyze/Clean.

function Format-WinCleanBytes {
    param([Parameter(Mandatory)][AllowNull()][Nullable[long]]$Bytes)

    if ($null -eq $Bytes) { return 'unknown' }
    $units = 'B', 'KB', 'MB', 'GB', 'TB'
    $value = [double]$Bytes
    $unitIndex = 0
    while ($value -ge 1024 -and $unitIndex -lt $units.Length - 1) {
        $value /= 1024
        $unitIndex++
    }
    if ($unitIndex -eq 0) { return "$Bytes B" }
    return '{0:N1} {1}' -f $value, $units[$unitIndex]
}
