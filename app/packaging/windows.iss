; The Windows installer (Inno Setup 6; Anvil's app/packaging/windows.iss is the model): installs for this user, without
; administrator rights, in %LOCALAPPDATA%\Programs\DSIP, with a Start menu entry and an uninstaller.
;
; The uninstaller keeps the app's folder (%APPDATA%\com.thevoiceguy.dsip\DSIP: its settings, and the identity's keys)
; unless the user says to delete it: a did:key identity cannot be rotated (DSIP §7.5), so its keys gone is the
; identity gone. Uninstalled silently, it keeps them.
;
;   iscc /DVersion=0.1.0 /DLabel=v0.1.0 /DBundle=<release dir> /DOut=<dir> windows.iss

#ifndef Version
  #error Version is required
#endif

[Setup]
AppId={{DF741C10-8480-46C0-B34E-9568F7B018C9}
AppName=DSIP
AppVerName=DSIP {#Version}
AppVersion={#Version}
AppPublisher=DSIP
AppPublisherURL=https://github.com/thevoiceguy/dsip-app
DefaultDirName={localappdata}\Programs\DSIP
DefaultGroupName=DSIP
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#Out}
OutputBaseFilename=DSIP-{#Label}-windows-x86_64-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\dsip.exe
UninstallDisplayName=DSIP
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; the Restart Manager asks a running DSIP to close
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Files]
Source: "{#Bundle}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\DSIP"; Filename: "{app}\dsip.exe"
Name: "{autodesktop}\DSIP"; Filename: "{app}\dsip.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\dsip.exe"; Description: "{cm:LaunchProgram,DSIP}"; Flags: nowait postinstall skipifsilent

[Code]
// The app's folder: path_provider's application support directory, named from the exe's CompanyName and ProductName
// (windows/runner/Runner.rc).
function DataDir: String;
begin
  Result := ExpandConstant('{userappdata}\com.thevoiceguy.dsip\DSIP');
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep <> usPostUninstall) or not DirExists(DataDir) then Exit;
  // Silent: the default button, No.
  if SuppressibleMsgBox('Also delete your DSIP identity and settings from this computer?' + #13#10#13#10
      + 'Your identity is its keys: deleted, it is gone for good, unless you have a copy. Keep them to use the same '
      + 'identity when you install DSIP again.' + #13#10#13#10 + DataDir,
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES then
  begin
    DelTree(DataDir, True, True, True);
    RemoveDir(ExpandConstant('{userappdata}\com.thevoiceguy.dsip'));
  end;
end;
