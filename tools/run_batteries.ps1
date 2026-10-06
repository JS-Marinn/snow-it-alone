<#
.SYNOPSIS
Runs the game's diagnostic batteries and fails if any of them does.

.DESCRIPTION
The batteries are this project's test suite: each one launches the real game with a
flag, exercises a system in the live simulation and reports what it measured. This
script runs them, reads their verdict and exits non-zero unless every battery passed.

A battery that crashes without reporting its verdict counts as a FAILURE, not as a
skip. That is deliberate: a crash must never be mistaken for a pass.

Four of the six batteries need a real graphics card, because the snow simulation
runs on the GPU. Those cannot run under -Headless and cannot run on a hosted CI
runner. Use -Headless to run the two that need no GPU.

.PARAMETER Godot
Path to the Godot executable. Defaults to $env:GODOT_BIN, then to the usual local
download location.

.PARAMETER Only
Run only these batteries, by flag name. Naming a battery explicitly runs it even
under -Headless, so this is also how the failure path gets tested.

.EXAMPLE
pwsh -File tools/run_batteries.ps1

.EXAMPLE
pwsh -File tools/run_batteries.ps1 -Only movement-lab,impact-lab

.EXAMPLE
pwsh -File tools/run_batteries.ps1 -Headless
#>
[CmdletBinding()]
param(
    [string]$Godot = $env:GODOT_BIN,
    [string]$Project = '',
    [string[]]$Only = @(),
    [switch]$Headless,
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'

if (-not $Project) {
    $Project = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
}

# Kind 'result'     -> must print "RESULT: <n> OK / <m> FAIL(URES)", with m = 0.
# Kind 'diagnostic' -> has no verdict of its own: it must finish and hold its budget.
$batteries = @(
    @{ Flag = 'save-roundtrip'; Name = 'Save slots';   Kind = 'result';     Gpu = $false },
    @{ Flag = 'ball-shape';     Name = 'Ball shape';   Kind = 'result';     Gpu = $false },
    @{ Flag = 'i18n-check';     Name = 'Translations'; Kind = 'result';     Gpu = $false },
    @{ Flag = 'diagnostics-harmless'; Name = 'Diagnostics safety'; Kind = 'result'; Gpu = $false },
    @{ Flag = 'movement-lab';   Name = 'Movement';     Kind = 'result';     Gpu = $true  },
    @{ Flag = 'impact-lab';     Name = 'Ball impacts'; Kind = 'result';     Gpu = $true  },
    @{ Flag = 'impact-matrix';  Name = 'Impact matrix'; Kind = 'result';    Gpu = $true  },
    @{ Flag = 'phys-demo';      Name = 'Physics';      Kind = 'result';     Gpu = $true  },
    @{ Flag = 'playground-check'; Name = 'Playground'; Kind = 'result';     Gpu = $true  },
    @{ Flag = 'beetle-roll';      Name = 'Dung beetle roll'; Kind = 'result'; Gpu = $true },
    @{ Flag = 'contact-burst';    Name = 'Contact burst'; Kind = 'result'; Gpu = $true },
    @{ Flag = 'hand-pack';        Name = 'Hand packing'; Kind = 'result'; Gpu = $true },
    @{ Flag = 'disposal-machine'; Name = 'Disposal machine'; Kind = 'result'; Gpu = $true },
    @{ Flag = 'toon-shot';        Name = 'Cel shading';  Kind = 'result'; Gpu = $true },
    @{ Flag = 'tool-ownership';   Name = 'Tool ownership'; Kind = 'result'; Gpu = $true },
    @{ Flag = 'reticle-act';      Name = 'Reticle and aim'; Kind = 'result'; Gpu = $true },
    @{ Flag = 'reticle-aim';      Name = 'Reticle needs close snow'; Kind = 'result'; Gpu = $true },
    @{ Flag = 'shovel-modes';     Name = 'Shovel load and push'; Kind = 'result'; Gpu = $true },
    @{ Flag = 'carve-quality';    Name = 'Snow carving'; Kind = 'diagnostic'; Gpu = $true; MinFps = 5 }
)

function Resolve-Godot {
    param([string]$Explicit)
    if ($Explicit) {
        if (Test-Path $Explicit) { return (Resolve-Path $Explicit).Path }
        throw "Godot not found at '$Explicit'."
    }
    $candidates = @(
        (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'),
        (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe'),
        '/usr/local/bin/godot',
        '/usr/bin/godot'
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    throw "Could not find Godot. Pass -Godot <path> or set the GODOT_BIN environment variable."
}

$godotPath = Resolve-Godot -Explicit $Godot
if (-not (Test-Path $Project)) { throw "Project folder not found: $Project" }

Write-Host ""
Write-Host "Batteries  ($Project)"
Write-Host "Godot      $godotPath"
Write-Host "Mode       $(if ($Headless) { 'headless (GPU batteries skipped)' } else { 'windowed' })"
Write-Host ""

$summary = @()
$failed = 0
$totalChecks = 0

Stop-Process -Name Godot -Force -ErrorAction SilentlyContinue

foreach ($b in $batteries) {
    if ($Only.Count -gt 0 -and $Only -notcontains $b.Flag) { continue }
    if ($Headless -and $b.Gpu -and $Only.Count -eq 0) {
        Write-Host ("  skip  {0,-14} needs a GPU" -f $b.Flag) -ForegroundColor DarkGray
        $summary += [pscustomobject]@{ Battery = $b.Name; Checks = 0; Verdict = 'skipped'; Note = 'needs a GPU' }
        continue
    }

    $outLog = Join-Path $Project "battery_$($b.Flag).log"
    $errLog = Join-Path $Project "battery_$($b.Flag).err.log"
    foreach ($f in @($outLog, $errLog)) { if (Test-Path $f) { Remove-Item $f -Force } }

    $engineArgs = @()
    if ($Headless) { $engineArgs += '--headless' }
    $engineArgs += @('--path', $Project, '--', "--$($b.Flag)")

    Write-Host ("  run   {0,-14} " -f $b.Flag) -NoNewline
    $started = Get-Date
    $proc = Start-Process -FilePath $godotPath -ArgumentList $engineArgs -PassThru -NoNewWindow `
        -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    $exited = $proc.WaitForExit($TimeoutSeconds * 1000)
    if (-not $exited) {
        try { $proc.Kill() } catch { }
        Write-Host ("TIMED OUT after {0}s" -f $TimeoutSeconds) -ForegroundColor Red
        $summary += [pscustomobject]@{ Battery = $b.Name; Checks = 0; Verdict = 'failed'; Note = "timed out after ${TimeoutSeconds}s" }
        $failed++
        continue
    }

    Start-Sleep -Milliseconds 250
    $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    $text = ''
    if (Test-Path $outLog) { $text += (Get-Content $outLog -Raw) }
    if (Test-Path $errLog) { $text += (Get-Content $errLog -Raw) }

    $verdict = 'failed'
    $note = ''
    $checks = 0

    $scriptErrors = [regex]::Matches($text, 'SCRIPT ERROR|Parse Error|Failed to load script')
    $match = [regex]::Match($text, 'RESULT:\s*(\d+)\s*(?:checks\s*)?OK\s*/\s*(\d+)\s*(?:FAIL|FAILURES|failures|FAILS)')

    if ($b.Kind -eq 'result') {
        if ($match.Success) {
            $checks = [int]$match.Groups[1].Value
            $failCount = [int]$match.Groups[2].Value
            if ($failCount -eq 0) { $verdict = 'passed' } else { $note = "$failCount failed checks" }
        }
        else {
            $note = 'no verdict printed (crashed?)'
        }
    }
    else {
        # Diagnostic: it has to finish, stay inside its frame budget and not throw.
        $fpsMatch = [regex]::Match($text, 'mean performance:\s*([0-9.]+)\s*FPS')
        $finished = $text -match '==== END ===='
        if (-not $finished) { $note = 'did not finish' }
        elseif (-not $fpsMatch.Success) { $note = 'no performance figure' }
        else {
            $fps = [double]$fpsMatch.Groups[1].Value
            $checks = 1
            if ($fps -ge $b.MinFps) { $verdict = 'passed'; $note = ("{0:N1} FPS" -f $fps) }
            else { $note = ("{0:N1} FPS, under the {1} FPS budget" -f $fps, $b.MinFps) }
        }
    }

    if ($scriptErrors.Count -gt 0 -and $verdict -eq 'passed') {
        $verdict = 'failed'
        $note = "$($scriptErrors.Count) script errors in the log"
    }

    if ($verdict -eq 'passed') {
        Write-Host ("pass  {0,3} checks in {1,5}s  {2}" -f $checks, $seconds, $note) -ForegroundColor Green
        $totalChecks += $checks
    }
    else {
        Write-Host ("FAIL  {0,5}s  {1}" -f $seconds, $note) -ForegroundColor Red
        $failed++
    }
    $summary += [pscustomobject]@{ Battery = $b.Name; Checks = $checks; Verdict = $verdict; Note = $note }
    Start-Sleep -Seconds 1
    Stop-Process -Name Godot -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("{0,-16} {1,7}  {2}" -f 'BATTERY', 'CHECKS', 'VERDICT')
Write-Host ("{0,-16} {1,7}  {2}" -f '---------------', '------', '-------')
foreach ($row in $summary) {
    $colour = switch ($row.Verdict) { 'passed' { 'Green' } 'skipped' { 'DarkGray' } default { 'Red' } }
    $checksText = if ($row.Checks -gt 0) { [string]$row.Checks } else { '-' }
    $noteText = if ($row.Note) { "  ($($row.Note))" } else { '' }
    Write-Host ("{0,-16} {1,7}  {2}{3}" -f $row.Battery, $checksText, $row.Verdict, $noteText) -ForegroundColor $colour
}
Write-Host ""
if ($failed -eq 0) {
    Write-Host "ALL GREEN  ($totalChecks checks)" -ForegroundColor Green
    Write-Host "Logs: battery_*.log next to the project" -ForegroundColor DarkGray
    exit 0
}
Write-Host "$failed BATTERY/BATTERIES FAILED" -ForegroundColor Red
Write-Host "Logs: battery_*.log next to the project" -ForegroundColor DarkGray
exit 1
