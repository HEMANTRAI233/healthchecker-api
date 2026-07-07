[Setup]

AppName=HealthChecker
AppVersion=1.0.0
PrivilegesRequired=admin
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

Source: "ensure-iis.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion

Source: "verify-iis.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion

Source: "verify-migration.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion

Source: "register-service.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion

Source: "unregister-service.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion

[Icons]

Name: "{group}\HealthChecker"; Filename: "{app}\HealthChecker.exe"

Name: "{commondesktop}\HealthChecker"; Filename: "{app}\HealthChecker.exe"

[Run]

Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\register-service.ps1"""; Flags: runhidden waituntilterminated

Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\ensure-iis.ps1"""; Flags: runhidden waituntilterminated

Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\configure-iis.ps1"""; Flags: runhidden waituntilterminated

Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\verify-iis.ps1"""; Flags: runhidden waituntilterminated

Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\verify-migration.ps1"""; Flags: runhidden waituntilterminated

Filename: "http://localhost/Healthchecker/"; Description: "Open HealthChecker in browser"; Flags: postinstall skipifsilent shellexec

[UninstallRun]

Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\unregister-service.ps1"""; Flags: runhidden waituntilterminated

[Code]
// Back up the existing binary before the installer overwrites it so that
// register-service.ps1 can restore it (binary rollback) if the new binary
// fails to start after a migration-then-crash scenario.
procedure CurStepChanged(CurStep: TSetupStep);
var
  OldExePath, BackupExePath: String;
begin
  if CurStep = ssInstFiles then
  begin
    OldExePath := ExpandConstant('{app}\HealthChecker.exe');
    BackupExePath := ExpandConstant('{app}\HealthChecker.exe.previous');
    if FileExists(OldExePath) then
    begin
      if not FileCopy(OldExePath, BackupExePath, False) then
        Log('WARNING: Could not back up ' + OldExePath + ' to ' + BackupExePath +
            ' -- binary rollback will not be available if the upgrade fails.');
    end;
  end;
end;