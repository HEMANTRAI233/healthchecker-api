Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$features = @(
    "IIS-WebServerRole",
    "IIS-WebServer",
    "IIS-CommonHttpFeatures",
    "IIS-StaticContent",
    "IIS-DefaultDocument",
    "IIS-HttpErrors",
    "IIS-ApplicationDevelopment",
    "IIS-ISAPIExtensions",
    "IIS-ISAPIFilter",
    "IIS-ManagementConsole"
)

foreach ($feature in $features) {
    $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature).State

    if ($state -ne "Enabled") {
        Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart | Out-Null
    }
}

$appCmd = Join-Path $env:WinDir "System32\inetsrv\appcmd.exe"

if (-not (Test-Path $appCmd)) {
    throw "IIS installation failed: appcmd.exe not found."
}

function Has-IISModule {
    param(
        [string]$ModuleName
    )

    $modules = & $appCmd list modules /text:name
    return $modules -match [Regex]::Escape($ModuleName)
}

function Ensure-Chocolatey {
    $choco = Get-Command choco -ErrorAction SilentlyContinue

    if ($null -ne $choco) {
        return
    }

    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

function Ensure-IISProxyDependencies {
    $rewriteInstalled = Has-IISModule -ModuleName "RewriteModule"
    $arrInstalled = Has-IISModule -ModuleName "ARRv2_Proxy"

    if ($rewriteInstalled -and $arrInstalled) {
        Write-Host "IIS proxy dependencies already installed."
        return
    }

    Write-Host "Installing IIS proxy dependencies (URL Rewrite + ARR)..."

    try {
        Ensure-Chocolatey
        choco install urlrewrite -y --no-progress
        choco install iis-arr -y --no-progress
    }
    catch {
        throw "Failed to install URL Rewrite/ARR automatically. Install both manually, then rerun setup. Error: $($_.Exception.Message)"
    }

    iisreset /restart | Out-Null

    $rewriteInstalled = Has-IISModule -ModuleName "RewriteModule"
    $arrInstalled = Has-IISModule -ModuleName "ARRv2_Proxy"

    if (-not $rewriteInstalled -or -not $arrInstalled) {
        throw "URL Rewrite or ARR is still missing after installation attempt. Install manually and rerun setup."
    }
}

Ensure-IISProxyDependencies

& $appCmd start site /site.name:"Default Web Site" | Out-Null
Write-Host "IIS is installed and Default Web Site is available."
