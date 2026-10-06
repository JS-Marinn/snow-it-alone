# Restores the flat-terrain snow system from backup/flat_snow_terrain.
#
# It restores an EXPLICIT list of paths, never "everything in the folder". An earlier version
# walked the folder and copied whatever it found, which meant the backup's own notes file
# overwrote the project README. A restore script that can copy something nobody intended is
# worse than no script.
param([switch]$IncludeProject)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$src  = Join-Path $repo "backup\flat_snow_terrain"
if (-not (Test-Path $src)) { Write-Error "No backup found at $src"; exit 1 }

$paths = @(
    "scripts\snow_field.gd",
    "scripts\player_controller.gd",
    "scripts\snowball.gd",
    "materials\snow_deform.gdshader",
    "materials\snow_deform.gdshader.uid",
    "shaders\snow_sim.glsl",
    "shaders\snow_sim.glsl.uid",
    "scenes\main.tscn",
    "scenes\playground.tscn"
)
if ($IncludeProject) { $paths += "project.godot" }

$copied = 0
foreach ($rel in $paths) {
    $from = Join-Path $src $rel
    if (-not (Test-Path $from)) { Write-Output "MISSING IN BACKUP: $rel"; continue }
    $to = Join-Path $repo $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $to -Parent) | Out-Null
    Copy-Item $from $to -Force
    Write-Output "restored: $rel"
    $copied++
}
Write-Output ""
Write-Output "Restored $copied paths. Restart the Godot editor so it reimports the shaders."
Write-Output "Then run tools\run_batteries.ps1 and expect ALL GREEN (14 batteries, 250 checks)."