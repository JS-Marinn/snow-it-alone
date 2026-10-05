<#
.SYNOPSIS
Generates or updates the en_XA pseudo-locale column in locale/strings.csv.

.DESCRIPTION
Takes English strings from locale/strings.csv, replaces vowels with accented
equivalents, wraps in brackets and pads to ~140% of original length while
preserving formatting tokens (e.g. %d, %s, %.1f).
Must be re-run whenever the English column changes.
#>
param(
    [string]$CsvPath = ''
)

$ErrorActionPreference = 'Stop'

if (-not $CsvPath) {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $projectDir = Split-Path -Parent $scriptDir
    $CsvPath = Join-Path $projectDir 'locale\strings.csv'
}

if (-not (Test-Path $CsvPath)) {
    throw "strings.csv not found at '$CsvPath'"
}

function ConvertTo-Pseudo {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return ''
    }

    # Split by format tokens like %d, %s, %.1f, %%, etc.
    $pattern = '(%[0-9.]*[a-zA-Z%])'
    $parts = [regex]::Split($Text, $pattern)
    $sb = New-Object System.Text.StringBuilder

    foreach ($part in $parts) {
        if ($part -match '^%[0-9.]*[a-zA-Z%]$') {
            [void]$sb.Append($part)
        }
        else {
            $trans = $part `
                -replace 'a', [char]0x00E5 `
                -replace 'e', [char]0x00EA `
                -replace 'i', [char]0x00EF `
                -replace 'o', [char]0x00F6 `
                -replace 'u', [char]0x00FB `
                -replace 'y', [char]0x00FD `
                -replace 'A', [char]0x00C5 `
                -replace 'E', [char]0x00CA `
                -replace 'I', [char]0x00CF `
                -replace 'O', [char]0x00D6 `
                -replace 'U', [char]0x00DB `
                -replace 'Y', [char]0x00DD
            [void]$sb.Append($trans)
        }
    }

    $accented = $sb.ToString()
    $targetLen = [int][Math]::Ceiling($Text.Length * 1.4)
    if ($targetLen -le ($Text.Length + 2)) {
        $targetLen = $Text.Length + 4
    }

    $baseWithBrackets = "[" + $accented + "]"
    if ($baseWithBrackets.Length -lt $targetLen) {
        $diff = $targetLen - $baseWithBrackets.Length
        $pad = [string]::new([char]0x007E, $diff) # '~'
        return "[" + $accented + $pad + "]"
    }
    return $baseWithBrackets
}

$rows = Import-Csv -Path $CsvPath

$outLines = @("keys,en,en_XA")
foreach ($r in $rows) {
    $k = $r.keys
    $en = $r.en.Replace('"', '""')
    $xa = (ConvertTo-Pseudo $r.en).Replace('"', '""')
    $outLines += "$k,""$en"",""$xa"""
}

$content = ($outLines -join "`r`n") + "`r`n"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($CsvPath, $content, $utf8NoBom)

Write-Host "Generated pseudo-locale en_XA for $($rows.Count) keys in $CsvPath"
