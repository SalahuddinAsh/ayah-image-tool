[Setup]
AppName=صورة آية
AppVersion=1.0.0
AppPublisherURL=https://github.com
DefaultDirName={autopf}\AyahImageTool
DefaultGroupName=صورة آية
OutputDir=installer_output
OutputBaseFilename=ayah_image_tool_setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\صورة آية"; Filename: "{app}\ayah_image_tool.exe"
Name: "{commondesktop}\صورة آية"; Filename: "{app}\ayah_image_tool.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ayah_image_tool.exe"; Description: "Launch Ayah Image Tool"; Flags: nowait postinstall skipifsilent
