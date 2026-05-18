param(
   [Parameter(Mandatory = $true)]
   [string]$UiVersion,

   [string]$Repo = "HEMANTRAI233/healthchecker-ui",

   [string]$GitHubToken = $env:GITHUB_TOKEN
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -----------------------------------
# CONFIGURATION
# -----------------------------------

$destinationDir = "web/dist"

$requestHeaders = @{
   "User-Agent" = "healthchecker-api-download-script"
}

if ($GitHubToken) {

   $requestHeaders["Authorization"] = "Bearer $GitHubToken"
}

$zipFile = $null

Write-Host ""
Write-Host "====================================="
Write-Host "DOWNLOADING UI ARTIFACT"
Write-Host "====================================="
Write-Host ""

Write-Host "Requested UI Version:"
Write-Host $UiVersion

try {

   # -----------------------------------
   # BUILD TAG CANDIDATES
   # -----------------------------------

   $tagCandidates = @($UiVersion)

   if ($UiVersion.StartsWith("ui-")) {

       $tagCandidates += $UiVersion.Substring(3)
   }
   else {

       $tagCandidates += "ui-$UiVersion"
   }

   $tagCandidates = $tagCandidates | Select-Object -Unique

   $release = $null
   $resolvedTag = $null

   # -----------------------------------
   # FIND RELEASE
   # -----------------------------------

   foreach ($tag in $tagCandidates) {

       $releaseApiUrl = "https://api.github.com/repos/$Repo/releases/tags/$tag"

       try {

           $release = Invoke-RestMethod `
               -Uri $releaseApiUrl `
               -Headers $requestHeaders

           $resolvedTag = $tag

           break
       }
       catch {

           $message = $_.Exception.Message

           if ($message -notmatch "404") {

               throw
           }
       }
   }

   if (-not $release) {

       throw "Release tag not found for repo '$Repo'. Tried: $($tagCandidates -join ', ')"
   }

   Write-Host ""
   Write-Host "Resolved Release Tag:"
   Write-Host $resolvedTag

   # -----------------------------------
   # FIND ZIP ASSET
   # -----------------------------------

   $zipAsset = $release.assets |
       Where-Object { $_.name -like "*.zip" } |
       Select-Object -First 1

   if (-not $zipAsset) {

       throw "No ZIP artifact found in release '$resolvedTag'"
   }

   $zipFile = $zipAsset.name
   $downloadUrl = $zipAsset.browser_download_url

   Write-Host ""
   Write-Host "Resolved Artifact:"
   Write-Host $zipFile

   Write-Host ""
   Write-Host "Download URL:"
   Write-Host $downloadUrl

   # -----------------------------------
   # DOWNLOAD ZIP
   # -----------------------------------

   Write-Host ""
   Write-Host "Downloading artifact..."

   Invoke-WebRequest `
       -Uri $downloadUrl `
       -Headers $requestHeaders `
       -OutFile $zipFile

   Write-Host ""
   Write-Host "Artifact downloaded successfully"

   # -----------------------------------
   # CLEAN EXISTING DIST
   # -----------------------------------

   if (Test-Path $destinationDir) {

       Write-Host ""
       Write-Host "Cleaning existing dist folder..."

       Remove-Item `
           $destinationDir `
           -Recurse `
           -Force
   }

   # -----------------------------------
   # CREATE DIST DIRECTORY
   # -----------------------------------

   Write-Host ""
   Write-Host "Creating dist directory..."

   New-Item `
       -ItemType Directory `
       -Path $destinationDir `
       -Force | Out-Null

   # -----------------------------------
   # EXTRACT ZIP
   # -----------------------------------

   Write-Host ""
   Write-Host "Extracting frontend artifact..."

   Expand-Archive `
       -Path $zipFile `
       -DestinationPath $destinationDir `
       -Force

   Write-Host ""
   Write-Host "Frontend artifact extracted successfully"

   # -----------------------------------
   # VERIFY EXTRACTION
   # -----------------------------------

   $indexPath = Join-Path $destinationDir "index.html"

   if (!(Test-Path $indexPath)) {

       throw "index.html not found after extraction"
   }

   Write-Host ""
   Write-Host "Verified:"
   Write-Host $indexPath

   Write-Host ""
   Write-Host "====================================="
   Write-Host "UI DOWNLOAD SUCCESSFUL"
   Write-Host "====================================="
}
catch {

   Write-Error ("UI download/extract failed: {0}" -f $_.Exception.Message)

   exit 1
}
finally {

   # -----------------------------------
   # CLEAN ZIP FILE
   # -----------------------------------

   if ($zipFile -and (Test-Path $zipFile)) {

       Remove-Item `
           $zipFile `
           -Force
   }
}