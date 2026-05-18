param(
    [string]$UiVersion = "",
    [string]$FrontendRepo = "HEMANTRAI233/healthchecker-ui",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot "build"
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

& (Join-Path $scriptRoot "download-ui.ps1") `
    -UiVersion $UiVersion `
    -FrontendRepo $FrontendRepo `
    -OutputDir (Join-Path $repoRoot "ui/dist")

Push-Location $repoRoot
try {
    go test ./...
    if ($LASTEXITCODE -ne 0) { throw "go test failed" }

    go vet ./...
    if ($LASTEXITCODE -ne 0) { throw "go vet failed" }

    $env:GOOS = "windows"
    $env:GOARCH = "amd64"
    $env:CGO_ENABLED = "0"

    $outExe = Join-Path $OutputDir "healthchecker.exe"
    # -H=windowsgui builds a no-console Windows binary (better installer UX).
    go build -ldflags "-s -w -H=windowsgui" -o $outExe .
    if ($LASTEXITCODE -ne 0) { throw "go build failed" }

    Write-Host "Build complete: $outExe"
}
finally {
    Pop-Location
}
