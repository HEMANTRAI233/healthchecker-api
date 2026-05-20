Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module WebAdministration

$appCmd = Join-Path $env:WinDir "System32\inetsrv\appcmd.exe"

if (-not (Test-Path $appCmd)) {
    throw "IIS appcmd not found. Ensure IIS is installed before running setup."
}

$modules = & $appCmd list modules /text:name

if ($modules -notmatch "RewriteModule") {
    throw "IIS URL Rewrite module is required but not installed. Install URL Rewrite 2.x and rerun setup."
}

if ($modules -notmatch "ARRv2_Proxy") {
    throw "IIS Application Request Routing (ARR) is required but not installed. Install ARR and rerun setup."
}

& $appCmd set config -section:system.webServer/proxy /enabled:"True" /preserveHostHeader:"True" /commit:apphost | Out-Null

$siteName = "Default Web Site"
$installRoot = Split-Path -Parent $PSScriptRoot
$proxyRoot = Join-Path $installRoot "iis-proxy"

$healthcheckerDir = Join-Path $proxyRoot "healthchecker"
$assetsDir = Join-Path $proxyRoot "assets"
$apiDir = Join-Path $proxyRoot "api"

New-Item -Path $healthcheckerDir -ItemType Directory -Force | Out-Null
New-Item -Path $assetsDir -ItemType Directory -Force | Out-Null
New-Item -Path $apiDir -ItemType Directory -Force | Out-Null

$healthcheckerWebConfig = @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name="HealthcheckerProxy" stopProcessing="true">
          <match url="(.*)" />
          <action type="Rewrite" url="http://127.0.0.1:8080/{R:1}" appendQueryString="true" />
        </rule>
      </rules>
    </rewrite>
  </system.webServer>
</configuration>
'@

$assetsWebConfig = @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name="AssetsProxy" stopProcessing="true">
          <match url="(.*)" />
          <action type="Rewrite" url="http://127.0.0.1:8080/assets/{R:1}" appendQueryString="true" />
        </rule>
      </rules>
    </rewrite>
  </system.webServer>
</configuration>
'@

$apiWebConfig = @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name="ApiProxy" stopProcessing="true">
          <match url="(.*)" />
          <action type="Rewrite" url="http://127.0.0.1:8080/api/{R:1}" appendQueryString="true" />
        </rule>
      </rules>
    </rewrite>
  </system.webServer>
</configuration>
'@

Set-Content -Path (Join-Path $healthcheckerDir "web.config") -Value $healthcheckerWebConfig -Encoding UTF8
Set-Content -Path (Join-Path $assetsDir "web.config") -Value $assetsWebConfig -Encoding UTF8
Set-Content -Path (Join-Path $apiDir "web.config") -Value $apiWebConfig -Encoding UTF8

if (Get-WebApplication -Site $siteName -Name "Healthchecker" -ErrorAction SilentlyContinue) {
    Remove-WebApplication -Site $siteName -Name "Healthchecker"
}

if (Get-WebApplication -Site $siteName -Name "assets" -ErrorAction SilentlyContinue) {
    Remove-WebApplication -Site $siteName -Name "assets"
}

if (Get-WebApplication -Site $siteName -Name "api" -ErrorAction SilentlyContinue) {
    Remove-WebApplication -Site $siteName -Name "api"
}

New-WebApplication -Site $siteName -Name "Healthchecker" -PhysicalPath $healthcheckerDir -ApplicationPool "DefaultAppPool" | Out-Null
New-WebApplication -Site $siteName -Name "assets" -PhysicalPath $assetsDir -ApplicationPool "DefaultAppPool" | Out-Null
New-WebApplication -Site $siteName -Name "api" -PhysicalPath $apiDir -ApplicationPool "DefaultAppPool" | Out-Null

Write-Host "IIS applications configured:" 
Write-Host "  http://localhost/Healthchecker"
