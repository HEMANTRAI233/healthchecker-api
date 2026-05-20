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

# Remove previous rules if they already exist (ignore errors when absent).
& $appCmd set config "Default Web Site" -section:system.webServer/rewrite/rules /-"[name='HealthcheckerProxy']" /commit:apphost 2>$null | Out-Null
& $appCmd set config "Default Web Site" -section:system.webServer/rewrite/rules /-"[name='AssetsProxy']" /commit:apphost 2>$null | Out-Null
& $appCmd set config "Default Web Site" -section:system.webServer/rewrite/rules /-"[name='ApiProxy']" /commit:apphost 2>$null | Out-Null

# Add site-level reverse proxy rules directly to applicationHost.config.
& $appCmd set config "Default Web Site" -section:system.webServer/rewrite/rules /+"[name='HealthcheckerProxy',patternSyntax='ECMAScript',stopProcessing='True',match.url='^Healthchecker/?(.*)',action.type='Rewrite',action.url='http://127.0.0.1:8080/{R:1}',action.appendQueryString='True']" /commit:apphost | Out-Null
& $appCmd set config "Default Web Site" -section:system.webServer/rewrite/rules /+"[name='AssetsProxy',patternSyntax='ECMAScript',stopProcessing='True',match.url='^assets/(.*)',action.type='Rewrite',action.url='http://127.0.0.1:8080/assets/{R:1}',action.appendQueryString='True']" /commit:apphost | Out-Null
& $appCmd set config "Default Web Site" -section:system.webServer/rewrite/rules /+"[name='ApiProxy',patternSyntax='ECMAScript',stopProcessing='True',match.url='^api/(.*)',action.type='Rewrite',action.url='http://127.0.0.1:8080/api/{R:1}',action.appendQueryString='True']" /commit:apphost | Out-Null

Write-Host "IIS applications configured:" 
Write-Host "  http://localhost/Healthchecker"
