param([string]$Destination = (Join-Path $PSScriptRoot '..\Windows-x64'))
$ErrorActionPreference='Stop'
$buildWork=Join-Path $PSScriptRoot '.build'
$env:DOTNET_CLI_HOME=Join-Path $buildWork 'dotnet-home'
$env:APPDATA=Join-Path $buildWork 'appdata'
$env:LOCALAPPDATA=Join-Path $buildWork 'localappdata'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE='false'
$env:NUGET_PACKAGES=Join-Path $buildWork 'nuget'
dotnet restore "$PSScriptRoot\Presenter\Presenter.csproj" --configfile "$PSScriptRoot\NuGet.Config" --nologo
if($LASTEXITCODE){throw 'Restore failed'}
dotnet build "$PSScriptRoot\Presenter\Presenter.csproj" -c Release --no-restore --nologo
if($LASTEXITCODE){throw 'Application build failed'}
if(Test-Path -LiteralPath $Destination){throw 'Build destination must be new'}
New-Item -ItemType Directory -Path $Destination | Out-Null
$appDestination=Join-Path $Destination 'Application'
New-Item -ItemType Directory -Path $appDestination | Out-Null
$built=Join-Path $PSScriptRoot 'Presenter\bin\Release\net10.0-windows'
Get-ChildItem -LiteralPath $built -File | Where-Object {$_.Extension -in '.exe','.dll','.json'} | Copy-Item -Destination $appDestination
Copy-Item -LiteralPath "$built\Sounds" -Destination $appDestination -Recurse
$framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
& "$framework\csc.exe" /nologo /target:exe /platform:x64 /optimize+ "/reference:$framework\System.Runtime.dll" "/reference:$framework\System.Runtime.WindowsRuntime.dll" "/out:$appDestination\NativePdf.exe" "$PSScriptRoot\Tools\NativePdf.cs"
if($LASTEXITCODE){throw 'Windows PDF adapter compilation failed'}
Copy-Item -LiteralPath "$built\Resources" -Destination $appDestination -Recurse
$hashes=[ordered]@{}
Get-ChildItem -LiteralPath $appDestination -File -Recurse | Sort-Object FullName | ForEach-Object {
 $relative=[IO.Path]::GetRelativePath($appDestination,$_.FullName).Replace('\','/')
 $hashes[$relative]=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
$hashes | ConvertTo-Json | Set-Content -LiteralPath "$appDestination\APP-SHA256.json" -Encoding utf8
$payload=Join-Path $PSScriptRoot 'Setup\payload.zip'
if(Test-Path -LiteralPath $payload){Remove-Item -LiteralPath $payload}
Compress-Archive -Path "$appDestination\*" -DestinationPath $payload
$framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
& "$framework\csc.exe" /nologo /target:winexe /platform:x64 /optimize+ /utf8output /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll /reference:Microsoft.CSharp.dll "/reference:$framework\System.IO.Compression.dll" "/reference:$framework\System.IO.Compression.FileSystem.dll" "/resource:$payload,payload.zip" "/out:$Destination\SmartTrainingPresenter-Setup-x64.exe" "$PSScriptRoot\Setup\Program.cs"
if($LASTEXITCODE){throw 'Setup compilation failed'}
Compress-Archive -Path "$appDestination\*" -DestinationPath "$Destination\SmartTrainingPresenter-0.6.1-B15-win-x64.zip"
