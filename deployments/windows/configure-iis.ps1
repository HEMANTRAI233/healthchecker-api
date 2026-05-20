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

& $appCmd start site /site.name:"Default Web Site" | Out-Null

$sitePath = "IIS:\Sites\Default Web Site"
$rulesFilter = "system.webServer/rewrite/rules"

function Remove-RewriteRuleIfExists {
    param(
        [string]$RuleName
    )

    $existingRule = Get-WebConfigurationProperty -PSPath $sitePath -Filter "$rulesFilter/rule[@name='$RuleName']" -Name "." -ErrorAction SilentlyContinue

    if ($null -ne $existingRule) {
        Remove-WebConfigurationProperty -PSPath $sitePath -Filter $rulesFilter -Name "." -AtElement @{ name = $RuleName }
    }
}

function Add-RewriteRule {
    param(
        [string]$RuleName,
        [string]$Pattern,
        [string]$TargetUrl
    )

    Remove-RewriteRuleIfExists -RuleName $RuleName

    Add-WebConfigurationProperty -PSPath $sitePath -Filter $rulesFilter -Name "." -Value @{ name = $RuleName; stopProcessing = "True" }

    Set-WebConfigurationProperty -PSPath $sitePath -Filter "$rulesFilter/rule[@name='$RuleName']/match" -Name "url" -Value $Pattern
    Set-WebConfigurationProperty -PSPath $sitePath -Filter "$rulesFilter/rule[@name='$RuleName']/action" -Name "type" -Value "Rewrite"
    Set-WebConfigurationProperty -PSPath $sitePath -Filter "$rulesFilter/rule[@name='$RuleName']/action" -Name "url" -Value $TargetUrl
    Set-WebConfigurationProperty -PSPath $sitePath -Filter "$rulesFilter/rule[@name='$RuleName']/action" -Name "appendQueryString" -Value "True"
}

Add-RewriteRule -RuleName "HealthcheckerProxy" -Pattern "^Healthchecker/?(.*)" -TargetUrl "http://127.0.0.1:8080/{R:1}"
Add-RewriteRule -RuleName "AssetsProxy" -Pattern "^assets/(.*)" -TargetUrl "http://127.0.0.1:8080/assets/{R:1}"
Add-RewriteRule -RuleName "ApiProxy" -Pattern "^api/(.*)" -TargetUrl "http://127.0.0.1:8080/api/{R:1}"

Write-Host "IIS applications configured:" 
Write-Host "  http://localhost/Healthchecker"
