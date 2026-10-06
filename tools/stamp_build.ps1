# Writes the current commit hash to build_hash.txt, which is what the game prints as
#     [BUILD] <hash>
# at startup. Run it after every commit that changes what the game does; it is deliberately a
# separate, explicit step rather than a git hook, because the stamp has to be part of the
# commit it describes and a hook cannot do that without amending history.
param(
    [string]$Repo = ''
)

$ErrorActionPreference = 'Stop'

if (-not $Repo) {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $Repo = Split-Path -Parent $scriptDir
}

$hash = (& git -C $Repo rev-parse --short HEAD 2>$null)
if (-not $hash) {
    Write-Error "Could not read a commit hash from '$Repo'. Is it a git repository?"
    exit 1
}
$hash = $hash.Trim()

$dirty = (& git -C $Repo status --porcelain 2>$null)
$suffix = ''
if ($dirty) { $suffix = '-dirty' }

$out = Join-Path $Repo 'build_hash.txt'
$text = $hash + $suffix
[System.IO.File]::WriteAllText($out, $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Stamped build_hash.txt with '$text'"
Write-Host "The game will print: [BUILD] $text"
