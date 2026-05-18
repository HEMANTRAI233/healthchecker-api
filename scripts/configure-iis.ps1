param(
    [string]$SiteName = "HealthChecker",
    [string]$AppPoolName = "HealthCheckerPool",
    [int]$IISPort = 80,
    [int]$BackendPort = 8080,
    [string]$ProxyRoot = "C:\ProgramData\HealthChecker\iis-proxy"
)

$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script as Administrator."
}

Import-Module WebAdministration

$rewrite = Get-WebGlobalModule -Name RewriteModule -ErrorAction SilentlyContinue
if (-not $rewrite) {
    throw "IIS URL Rewrite Module is required. Install URL Rewrite + ARR, then re-run this script."
}

New-Item -ItemType Directory -Path $ProxyRoot -Force | Out-Null

$webConfigPath = Join-Path $ProxyRoot "web.config"
@"
<?xml version=""1.0"" encoding=""utf-8""?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name=""HealthCheckerProxy"" stopProcessing=""true"">
          <match url=""(.*)"" />
          <action type=""Rewrite"" url=""http://127.0.0.1:$BackendPort/{R:1}"" />
        </rule>
      </rules>
    </rewrite>
  </system.webServer>
</configuration>
"@ | Set-Content -Path $webConfigPath -Encoding UTF8

$appCmd = "$env:WinDir\System32\inetsrv\appcmd.exe"
& $appCmd set config -section:system.webServer/proxy /enabled:"True" /commit:apphost | Out-Null

if (-not (Test-Path "IIS:\AppPools\$AppPoolName")) {
    New-WebAppPool -Name $AppPoolName | Out-Null
}
Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name processModel.identityType -Value ApplicationPoolIdentity

$existingSite = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
if ($existingSite) {
    Remove-Website -Name $SiteName
}

New-Website -Name $SiteName -Port $IISPort -PhysicalPath $ProxyRoot -ApplicationPool $AppPoolName | Out-Null
iisreset | Out-Null

Write-Host "IIS reverse proxy configured."
Write-Host "Browse: http://localhost:$IISPort/"
