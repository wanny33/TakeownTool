$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$sedPath = Join-Path $env:TEMP 'TakeownTool.sed'
$outputPath = Join-Path $root 'TakeownTool.exe'
$sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=I
InstallPrompt=%InstallPrompt%
DisplayLicense=
FinishMessage=%FinishMessage%
TargetName=$outputPath
FriendlyName=Takeown Tool
AppLaunched=Run-TakeownTool.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
FinishMessage=
[SourceFiles]
SourceFiles0=$root
[SourceFiles0]
TakeownTool.ps1=
Run-TakeownTool.cmd=
"@
Set-Content -LiteralPath $sedPath -Value $sed -Encoding ASCII
$process = Start-Process -FilePath 'iexpress.exe' -ArgumentList @('/N', '/Q', $sedPath) -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "IExpress 失敗，exit code $($process.ExitCode)。" }
if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw 'IExpress 未產生 TakeownTool.exe。' }
Write-Output "Created $outputPath"