Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

& $appCmd start site /site.name:"Default Web Site" | Out-Null

$siteRoot = Join-Path $env:SystemDrive "inetpub\wwwroot"

$healthcheckerDir = Join-Path $siteRoot "Healthchecker"
$assetsDir = Join-Path $siteRoot "assets"
$apiDir = Join-Path $siteRoot "api"

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

Write-Host "IIS applications configured:" 
Write-Host "  http://localhost/Healthchecker"
