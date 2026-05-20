Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptVersion = "2026-05-20.2"

$logDir = Join-Path $env:ProgramData "HealthChecker"
New-Item -Path $logDir -ItemType Directory -Force | Out-Null
$logPath = Join-Path $logDir "configure-iis.log"
Start-Transcript -Path $logPath -Append | Out-Null
Write-Host "HealthChecker configure-iis script version: $scriptVersion"

$appCmd = Join-Path $env:WinDir "System32\inetsrv\appcmd.exe"

if (-not (Test-Path $appCmd)) {
    throw "IIS appcmd not found. Ensure IIS is installed before running setup."
}

function Get-IISModules {
    return & $appCmd list modules /text:name
}

function Test-RewriteAndArrPresence {
    $modules = Get-IISModules
    $hasRewrite = $modules -match "RewriteModule"
    $hasArr = $modules -match "ARRv2_Proxy"

    return @{
        HasRewrite = $hasRewrite
        HasArr = $hasArr
        Modules = $modules
    }
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

function Install-MsiPackage {
    param(
        [string]$Url,
        [string]$Name
    )

    $downloadPath = Join-Path $env:TEMP ("{0}.msi" -f $Name)
    Invoke-WebRequest -Uri $Url -OutFile $downloadPath -UseBasicParsing
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$downloadPath`" /qn /norestart" -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Failed installing $Name MSI. ExitCode=$($process.ExitCode)"
    }
}

function Ensure-RewriteAndArr {
    $state = Test-RewriteAndArrPresence
    $hasRewrite = $state.HasRewrite
    $hasArr = $state.HasArr

    Write-Host "Initial module detection: RewriteModule=$hasRewrite ARRv2_Proxy=$hasArr"

    if ($hasRewrite -and $hasArr) {
        return
    }

    Write-Host "Installing missing IIS proxy dependencies..."

    $installed = $false

    try {
        Ensure-Chocolatey
        choco install urlrewrite -y --no-progress
        choco install iis-arr -y --no-progress
        $installed = $true
    }
    catch {
        Write-Host "Chocolatey install path failed: $($_.Exception.Message)"
    }

    if (-not $installed) {
        try {
            $winget = Get-Command winget -ErrorAction SilentlyContinue

            if ($null -ne $winget) {
                winget install --id Microsoft.URLRewrite --exact --silent --accept-source-agreements --accept-package-agreements
                winget install --id Microsoft.IIS.ARR --exact --silent --accept-source-agreements --accept-package-agreements
                $installed = $true
            }
        }
        catch {
            Write-Host "winget install path failed: $($_.Exception.Message)"
        }
    }

    if (-not $installed) {
        # Direct MSI fallback from Microsoft download endpoints.
        Install-MsiPackage -Url "https://download.microsoft.com/download/D/D/9/DD9A82D0-1E3C-4AF2-8CB0-819C8D6D54A8/rewrite_amd64_en-US.msi" -Name "urlrewrite"
        Install-MsiPackage -Url "https://download.microsoft.com/download/9/5/D/95D5A1B2-4D63-43A1-A35F-92357F7C1D8B/requestRouter_amd64.msi" -Name "iis-arr"
    }

    iisreset /restart | Out-Null

    $state = Test-RewriteAndArrPresence
    $hasRewrite = $state.HasRewrite
    $hasArr = $state.HasArr

    Write-Host "Post-install module detection: RewriteModule=$hasRewrite ARRv2_Proxy=$hasArr"

    if (-not $hasRewrite -or -not $hasArr) {
        Write-Host "Forcing package reinstallation to repair IIS module registration..."

        try {
            Ensure-Chocolatey
            choco upgrade urlrewrite -y --force --no-progress
            choco upgrade iis-arr -y --force --no-progress
        }
        catch {
            Write-Host "Forced package repair failed: $($_.Exception.Message)"
        }

        iisreset /restart | Out-Null

        $state = Test-RewriteAndArrPresence
        $hasRewrite = $state.HasRewrite
        $hasArr = $state.HasArr

        Write-Host "Post-repair module detection: RewriteModule=$hasRewrite ARRv2_Proxy=$hasArr"
    }

    if (-not $hasRewrite -or -not $hasArr) {
        Write-Host "IIS modules visible to appcmd:"
        Write-Host $state.Modules
        throw "IIS URL Rewrite/ARR installation failed or modules are not registered in IIS. Manually reinstall URL Rewrite and ARR, run iisreset, then rerun setup."
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
