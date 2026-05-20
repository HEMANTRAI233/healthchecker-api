[Setup]

AppName=HealthChecker
AppVersion=1.0.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DefaultDirName={pf}\HealthChecker
DefaultGroupName=HealthChecker
OutputDir=..\..
OutputBaseFilename=HealthChecker-Setup
Compression=lzma
SolidCompression=yes

[Files]

Source: "..\..\build\HealthChecker.exe"; DestDir: "{app}"; Flags: ignoreversion

Source: "..\..\build\config\app.env"; DestDir: "{app}\config"; Flags: ignoreversion

Source: "configure-iis.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion

Source: "register-service.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion

Source: "unregister-service.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion

[Icons]

Name: "{group}\HealthChecker"; Filename: "{app}\HealthChecker.exe"

Name: "{commondesktop}\HealthChecker"; Filename: "{app}\HealthChecker.exe"

[Run]

Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\register-service.ps1"""; Flags: runhidden waituntilterminated runascurrentuser

Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\configure-iis.ps1"""; Flags: runhidden waituntilterminated runascurrentuser

Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""if (!(Test-Path 'C:\inetpub\wwwroot\Healthchecker\healthchecker-iis-configured.txt')) { Write-Error 'IIS configuration marker not found. Check C:\ProgramData\HealthChecker\configure-iis.log'; exit 1 }"""; Flags: runhidden waituntilterminated runascurrentuser

Filename: "http://localhost/Healthchecker/"; Description: "Open HealthChecker in browser"; Flags: postinstall skipifsilent shellexec

[UninstallRun]

Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\unregister-service.ps1"""; Flags: runhidden waituntilterminated runascurrentuser