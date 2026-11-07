#define MyAppName "好分数 · 原生工作台"
#define MyAppVersion "2.3.0"
#define MyAppPublisher "HFS Native Workbench"
#define MyAppExeName "hfs_flutter.exe"

[Setup]
AppId={{8E9D5C42-3A71-4B8F-9C2E-6D41B5A02100}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} v{#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\HfsFlutterWorkbench
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\out
OutputBaseFilename=hfs_flutter_windows_x64_setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "default"; MessagesFile: "compiler:Default.isl"

[Messages]
SetupWindowTitle=安装 - %1
ButtonNext=下一步(&N) >
ButtonBack=< 上一步(&B)
ButtonInstall=立即安装(&I)
ButtonFinish=完成(&F)
ButtonCancel=取消
SelectDirDesc=要把 %1 安装到哪里？
SelectDirLabel3=安装程序将在以下文件夹中安装 %1。
SelectTasksDesc=选择安装 %1 时要执行的附加任务：
ReadyLabel1=现在准备开始安装 %1 到您的电脑中。
FinishedHeadingLabel=%1 安装完成
FinishedLabelNoIcons=安装程序已在您的电脑上完成安装 %1。
FinishedLabel=安装程序已在您的电脑上完成安装 %1。可通过选择安装的快捷方式启动应用程序。

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式 (&D)"; GroupDescription: "附加桌面图标:"; Flags: checkedonce

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "立即启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
