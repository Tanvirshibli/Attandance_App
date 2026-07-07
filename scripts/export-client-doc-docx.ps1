#Requires -Version 5.1
<#
.SYNOPSIS
  Exports CLIENT_ANDROID_APP_DEVELOPMENT_PLAN.md to .docx with embedded diagram images.

.DESCRIPTION
  Requires Pandoc. Run render-client-doc-diagrams.ps1 first to generate PNGs.
#>
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$mdPath = Join-Path $root 'docs\CLIENT_ANDROID_APP_DEVELOPMENT_PLAN.md'
$docxPath = Join-Path $root 'docs\CLIENT_ANDROID_APP_DEVELOPMENT_PLAN.docx'
$imagesDir = Join-Path $root 'docs\images\client-plan'

if (-not (Test-Path $mdPath)) {
    Write-Error "Markdown file not found: $mdPath"
    exit 1
}

$pngCount = (Get-ChildItem -Path $imagesDir -Filter '*.png' -ErrorAction SilentlyContinue).Count
if ($pngCount -lt 4) {
    Write-Warning "Only $pngCount PNG(s) found in $imagesDir. Run render-client-doc-diagrams.ps1 first."
}

if (-not (Get-Command pandoc -ErrorAction SilentlyContinue)) {
    Write-Error "Pandoc not found. Install with: winget install JohnMacFarlane.Pandoc"
    exit 1
}

Push-Location $root
try {
    Write-Host "Exporting $mdPath to $docxPath ..."
    pandoc $mdPath `
        -o $docxPath `
        --resource-path=docs `
        --from markdown `
        --toc `
        --metadata 'title=PPHL Attendance Android App - Client Development Plan'

    if (Test-Path $docxPath) {
        Write-Host "Done: $docxPath"
    } else {
        Write-Error 'Export failed - .docx was not created.'
        exit 1
    }
}
finally {
    Pop-Location
}
