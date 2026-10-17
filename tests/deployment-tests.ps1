#requires -version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. "$root\scripts\common.ps1"
. "$root\scripts\deployment-common.ps1"
Assert-WindowsPowerShell
Assert-HostBuild
$temp=Join-Path $env:TEMP ('music-deploy-tests-'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $temp 'fixture'
New-Item -ItemType Directory -Path $source -Force | Out-Null
$text=[IO.File]::ReadAllText((Join-Path $root 'tests\fixtures\AppxManifest.xml')).Replace('MinVersion="10.0.19044.0"','MinVersion="10.0.19045.0"')
[IO.File]::WriteAllText((Join-Path $source 'AppxManifest.xml'),$text)
[IO.File]::WriteAllText((Join-Path $source 'AppleMusic.exe'),'fixture-not-executable')
[IO.File]::WriteAllText((Join-Path $source 'AMPLibraryAgent.exe'),'fixture-not-executable')
$zip=Join-Path $temp 'fixture.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($source,$zip)
$info=Get-MusicSource $zip
if (-not $info.IsArchive) { throw 'FAIL: ZIP identification' }
$destination=Join-Path $temp 'extracted'
Expand-MusicArchive $zip $destination
$null=Get-MusicSource $destination
if ((Get-FileHash -LiteralPath (Join-Path $destination 'AppleMusic.exe')).Hash -ne (Get-FileHash -LiteralPath (Join-Path $source 'AppleMusic.exe')).Hash) { throw 'FAIL: Extract hash' }
$rejected=$false
try { Expand-MusicArchive $zip $destination } catch { $rejected=$true }
if (-not $rejected) { throw 'FAIL: Existing destination accepted' }
$cases=@('../escape.txt','/absolute.txt','C:\escape.txt','foo:ads','folder/CON.txt','trailing./file.txt','nested/../../escape.txt','duplicated-case')
$i=0
foreach ($badPath in $cases) {
    $badZip=Join-Path $temp ('bad-'+$i+'.zip')
    $archive=[IO.Compression.ZipFile]::Open($badZip,[IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in @('AppxManifest.xml','AppleMusic.exe','AMPLibraryAgent.exe')) { $null=$archive.CreateEntry($name) }
        if ($badPath -eq 'duplicated-case') { $null=$archive.CreateEntry('applemusic.exe') }
        else { $null=$archive.CreateEntry($badPath) }
    } finally { $archive.Dispose() }
    $badDestination=Join-Path $temp ('bad-output-'+$i)
    $rejected=$false
    try { Expand-MusicArchive $badZip $badDestination } catch { $rejected=$true }
    if (-not $rejected -or (Test-Path -LiteralPath $badDestination)) { throw "FAIL: Unsafe ZIP accepted: $badPath" }
    $i++
}
# 所有 Appx/进程命令在预检测试里替换为本地假数据；任何实际部署调用立刻失败。
function Get-AppxPackage {
    param($Name)
    if ($Name -like 'Microsoft.VCLibs*') {
        [pscustomobject]@{Name=$Name;Version=[version]'14.0.99999.0';Publisher='CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US';Architecture='X64'}
    }
}
function Get-Process { param($Name,$ErrorAction) }
function Add-AppxPackage { throw 'FAIL: Preflight attempted actual deployment' }
$script:dependencyMissing=$false
if (@(Get-DependencyInstallPlan $info @()).Count) { throw 'FAIL: unexpected dependency install' }
& "$root\deploy.ps1" -SourcePackage $zip -CheckOnly
& "$root\deploy.ps1" -SourcePackage $source -WhatIf
function Get-AppxPackage { param($Name) }
$rejected=$false
try { $null=Get-DependencyInstallPlan $info @() } catch { $rejected=$true }
if (-not $rejected) { throw 'FAIL: Missing dependencies not rejected' }
$rejected=$false
try { $null=Get-DependencyInstallPlan $info @($zip) } catch { $rejected=$true }
if (-not $rejected) { throw 'FAIL: ZIP accepted as dependency package' }
Write-Host 'PASS: directory/ZIP inputs; extraction hashes; overwrite rejection; 8 unsafe ZIP cases; CheckOnly/WhatIf without deployment; missing/invalid dependency rejection.'
Write-Host "测试材料保留：$temp；未注册应用、安装依赖或启动 Apple Music。"
