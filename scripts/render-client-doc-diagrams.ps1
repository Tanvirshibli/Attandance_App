#Requires -Version 5.1
<#
.SYNOPSIS
  Renders client-plan Mermaid diagrams to PNG for Google Docs import.

.DESCRIPTION
  Requires Node.js (npx). Outputs PNG files to docs/images/client-plan/.
#>
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$inputDir = Join-Path $root 'docs\diagrams\client-plan'
$outputDir = Join-Path $root 'docs\images\client-plan'

if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js/npx not found. Install Node.js LTS, then re-run this script."
    exit 1
}

if (-not (Test-Path $inputDir)) {
    Write-Error "Diagram source folder not found: $inputDir"
    exit 1
}

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$mmdFiles = Get-ChildItem -Path $inputDir -Filter '*.mmd' | Sort-Object Name
if ($mmdFiles.Count -eq 0) {
    Write-Error "No .mmd files found in $inputDir"
    exit 1
}

Push-Location $root
try {
    Write-Host "Rendering $($mmdFiles.Count) Mermaid diagram(s) ..."
    foreach ($file in $mmdFiles) {
        $outFile = Join-Path $outputDir ($file.BaseName + '.png')
        Write-Host "  $($file.Name) -> $($file.BaseName).png"
        npx -y @mermaid-js/mermaid-cli `
            -i $file.FullName `
            -o $outFile `
            -b white `
            -s 2
    }

    $pngs = Get-ChildItem -Path $outputDir -Filter '*.png'
    if ($pngs.Count -lt $mmdFiles.Count) {
        Write-Warning "Expected $($mmdFiles.Count) PNG files; found $($pngs.Count)."
    }

    Write-Host "Done. Generated:"
    $pngs | ForEach-Object { Write-Host "  $($_.FullName)" }
}
finally {
    Pop-Location
}
