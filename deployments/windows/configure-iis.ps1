Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logDir = Join-Path $env:ProgramData "HealthChecker"
New-Item -Path $logDir -ItemType Directory -Force | Out-Null
$logPath = Join-Path $logDir "configure-iis.log"
Start-Transcript -Path $logPath -Append | Out-Null

$appCmd = Join-Path $env:WinDir "System32\inetsrv\appcmd.exe"

if (-not (Test-Path $appCmd)) {
    throw "IIS appcmd not found. Ensure IIS is installed before running setup."
}

function Get-IISModules {
    return & $appCmd list modules /text:name
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

function Ensure-RewriteAndArr {
    $modules = Get-IISModules
    $hasRewrite = $modules -match "RewriteModule"
    $hasArr = $modules -match "ARRv2_Proxy"

    if ($hasRewrite -and $hasArr) {
        return
    }

    Write-Host "Installing missing IIS proxy dependencies..."

    Ensure-Chocolatey
    choco install urlrewrite -y --no-progress
    choco install iis-arr -y --no-progress
    iisreset /restart | Out-Null

    $modules = Get-IISModules
    $hasRewrite = $modules -match "RewriteModule"
    $hasArr = $modules -match "ARRv2_Proxy"

    if (-not $hasRewrite -or -not $hasArr) {
        throw "IIS URL Rewrite/ARR installation failed. Install URL Rewrite 2.x and ARR manually, then rerun setup."
    }
}

Ensure-RewriteAndArr

& $appCmd set config -section:system.webServer/proxy /enabled:"True" /preserveHostHeader:"True" /commit:apphost | Out-Null

& $appCmd start site /site.name:"Default Web Site" | Out-Null

$siteRootRaw = (& $appCmd list site "Default Web Site" /text:physicalPath).Trim()
$siteRoot = [Environment]::ExpandEnvironmentVariables($siteRootRaw)

if (-not (Test-Path $siteRoot)) {
    throw "IIS site root not found at: $siteRoot"
}

$healthcheckerDir = Join-Path $siteRoot "Healthchecker"
New-Item -Path $healthcheckerDir -ItemType Directory -Force | Out-Null

$healthcheckerFolderWebConfigPath = Join-Path $healthcheckerDir "web.config"
$healthcheckerFolderWebConfig = @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
    <system.webServer>
        <rewrite>
            <rules>
                <rule name="HealthcheckerFolderProxyRoot" stopProcessing="true">
                    <match url="^$" />
                    <action type="Rewrite" url="http://127.0.0.1:8080/" appendQueryString="true" />
                </rule>
                <rule name="HealthcheckerFolderProxySubPath" stopProcessing="true">
                    <match url="(.*)" />
                    <action type="Rewrite" url="http://127.0.0.1:8080/{R:1}" appendQueryString="true" />
                </rule>
            </rules>
        </rewrite>
    </system.webServer>
</configuration>
'@

Set-Content -Path $healthcheckerFolderWebConfigPath -Value $healthcheckerFolderWebConfig -Encoding UTF8

$rootWebConfigPath = Join-Path $siteRoot "web.config"

$rootWebConfig = @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
    <system.webServer>
        <rewrite>
            <rules>
                <rule name="HealthcheckerProxyRoot" stopProcessing="true">
                    <match url="^Healthchecker/?$" />
                    <action type="Rewrite" url="http://127.0.0.1:8080/" appendQueryString="true" />
                </rule>
                <rule name="HealthcheckerProxySubPath" stopProcessing="true">
                    <match url="^Healthchecker/(.*)" />
                    <action type="Rewrite" url="http://127.0.0.1:8080/{R:1}" appendQueryString="true" />
                </rule>
                <rule name="AssetsProxy" stopProcessing="true">
                    <match url="^assets/(.*)" />
                    <action type="Rewrite" url="http://127.0.0.1:8080/assets/{R:1}" appendQueryString="true" />
                </rule>
                <rule name="ApiProxy" stopProcessing="true">
                    <match url="^api/(.*)" />
                    <action type="Rewrite" url="http://127.0.0.1:8080/api/{R:1}" appendQueryString="true" />
                </rule>
            </rules>
        </rewrite>
    </system.webServer>
</configuration>
'@

Set-Content -Path $rootWebConfigPath -Value $rootWebConfig -Encoding UTF8

$markerPath = Join-Path $healthcheckerDir "healthchecker-iis-configured.txt"
Set-Content -Path $markerPath -Value "configured on $(Get-Date -Format o)" -Encoding UTF8

Write-Host "IIS applications configured:" 
Write-Host "  http://localhost/Healthchecker"
Write-Host "IIS setup log: $logPath"

Stop-Transcript | Out-Null
