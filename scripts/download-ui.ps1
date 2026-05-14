param(
   [Parameter(Mandatory = $true)]
   [string]$UiVersion,
   [string]$Repo = "HEMANTRAI233/healthchecker-ui",
   [string]$GitHubToken = $env:GITHUB_TOKEN
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$destinationDir = "web"
$requestHeaders = @{ "User-Agent" = "healthchecker-api-download-script" }
if ($GitHubToken) {
   $requestHeaders["Authorization"] = "Bearer $GitHubToken"
}
$zipFile = $null

Write-Host ""
Write-Host "================================"
Write-Host "Downloading UI artifact..."
Write-Host "================================"
Write-Host ""

Write-Host "Version:"
Write-Host $UiVersion

try {
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
   foreach ($tag in $tagCandidates) {
      $releaseApiUrl = "https://api.github.com/repos/$repo/releases/tags/$tag"
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
      throw "Release tag not found for repo '$Repo'. Tried: $($tagCandidates -join ', '). If this repo is private, provide -GitHubToken or set GITHUB_TOKEN."
   }

   Write-Host ""
   Write-Host "Resolved tag:"
   Write-Host $resolvedTag

   $zipAsset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
   if (-not $zipAsset) {
      throw "No .zip asset found for release tag '$resolvedTag'."
   }

   $zipFile = $zipAsset.name
   $url = $zipAsset.browser_download_url

   Write-Host ""
   Write-Host "Resolved asset:"
   Write-Host $zipFile
   Write-Host ""
   Write-Host "Download URL:"
   Write-Host $url

   Invoke-WebRequest `
      -Uri $url `
      -Headers $requestHeaders `
      -OutFile $zipFile

   Write-Host ""
   Write-Host "Download completed successfully"

   if (Test-Path $destinationDir) {
      Write-Host ""
      Write-Host "Cleaning up existing web directory..."
      Remove-Item $destinationDir -Recurse -Force
   }

   New-Item `
      -ItemType Directory `
      -Path $destinationDir | Out-Null

   Write-Host ""
   Write-Host "Extracting artifact..."

   Expand-Archive `
      -Path $zipFile `
      -DestinationPath $destinationDir

   Write-Host ""
   Write-Host "Frontend artifact extracted successfully"
}
catch {
   Write-Error ("UI download/extract failed: {0}" -f $_.Exception.Message)
   exit 1
}
finally {
   if ($zipFile -and (Test-Path $zipFile)) {
      Remove-Item $zipFile -Force
   }
}