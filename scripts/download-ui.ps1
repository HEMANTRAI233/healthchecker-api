param(
    [string]$UiVersion = "",
    [string]$FrontendRepo = "HEMANTRAI233/healthchecker-ui",
    [string]$AssetName = "dist.zip",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot "ui/dist"
}

if ([string]::IsNullOrWhiteSpace($UiVersion)) {
    $uiVersionFile = Join-Path $repoRoot "UI_VERSION"
    if (Test-Path $uiVersionFile) {
        $UiVersion = (Get-Content $uiVersionFile -Raw).Trim()
    }
}

if ([string]::IsNullOrWhiteSpace($UiVersion)) {
    throw "UI version not provided. Set -UiVersion or add UI_VERSION file."
}

$headers = @{
    "User-Agent" = "healthchecker-api-build"
    "Accept"     = "application/vnd.github+json"
}
if ($env:GITHUB_TOKEN) {
    $headers["Authorization"] = "Bearer $($env:GITHUB_TOKEN)"
}

if ($UiVersion -eq "latest") {
    $releaseUrl = "https://api.github.com/repos/$FrontendRepo/releases/latest"
} else {
    $releaseUrl = "https://api.github.com/repos/$FrontendRepo/releases/tags/$UiVersion"
}

Write-Host "Resolving UI release: $UiVersion ($FrontendRepo)"
$release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -Method Get
$resolvedTag = "$($release.tag_name)".Trim()
if ($resolvedTag -notmatch '^ui-v\d+\.\d+\.\d+$') {
    throw "Resolved UI tag '$resolvedTag' is invalid. Expected format: ui-v<major>.<minor>.<patch>."
}
$asset = $release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
if (-not $asset) {
    throw "Release '$resolvedTag' does not contain asset '$AssetName'."
}

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "healthchecker-ui-download"
if (Test-Path $tmpDir) {
    Remove-Item -Path $tmpDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tmpDir | Out-Null

$zipPath = Join-Path $tmpDir $AssetName
Write-Host "Downloading UI artifact: $($asset.browser_download_url)"
Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $zipPath

if (Test-Path $OutputDir) {
    Remove-Item -Path $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDir | Out-Null
Expand-Archive -Path $zipPath -DestinationPath $OutputDir -Force

Write-Host "UI artifact extracted to: $OutputDir"
