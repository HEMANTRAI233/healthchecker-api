[Setup]

AppName=HealthChecker
AppVersion=1.0.0
DefaultDirName={pf}\HealthChecker
DefaultGroupName=HealthChecker
OutputDir=..\..
OutputBaseFilename=HealthChecker-Setup
Compression=lzma
SolidCompression=yes

[Files]

Source: "..\..\build\HealthChecker.exe"; DestDir: "{app}"; Flags: ignoreversion

Source: "..\..\build\config\app.env"; DestDir: "{app}\config"; Flags: ignoreversion

[Icons]

Name: "{group}\HealthChecker"; Filename: "{app}\HealthChecker.exe"

Name: "{commondesktop}\HealthChecker"; Filename: "{app}\HealthChecker.exe"

[Run]

Filename: "{app}\HealthChecker.exe"; Description: "Launch HealthChecker"; Flags: nowait postinstall skipifsilent