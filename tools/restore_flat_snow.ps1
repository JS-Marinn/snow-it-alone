# Restores the flat-terrain snow system from backup/flat_snow_terrain.
# Copies over the project and reports what it touched. Restart the editor afterwards.
param([switch]$IncludeProject)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$src  = Join-Path $repo "backup\flat_snow_terrain"
if (-not (Test-Path $src)) { Write-Error "No backup found at $src"; exit 1 }
$copied = 0
Get-ChildItem $src -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($src.Length + 1)
    if (-not $IncludeProject -and $rel -eq "project.godot") {
        Write-Output "skipped (use -IncludeProject): $rel"
        return
    }
    $target = Join-Path $repo $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    Copy-Item $_.FullName $target -Force
    Write-Output "restored: $rel"
    $script:copied++
}
Write-Output ""
Write-Output "Restored $copied files. Restart the Godot editor so it reimports the shaders."
Write-Output "Then run tools\run_batteries.ps1 and expect ALL GREEN."