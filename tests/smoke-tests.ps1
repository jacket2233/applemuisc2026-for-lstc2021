#requires -version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$workspace=Join-Path ([IO.Path]::GetTempPath()) ('applemusic-project-test-'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $workspace 'fixture'
New-Item -ItemType Directory -Path $source -Force | Out-Null
$text=[IO.File]::ReadAllText((Join-Path $root 'tests\fixtures\AppxManifest.xml')).Replace('MinVersion="10.0.19044.0"','MinVersion="10.0.19045.0"')
[IO.File]::WriteAllText((Join-Path $source 'AppxManifest.xml'),$text)
# 仅供复制和哈希单元测试的文本，不作为可运行 Apple 程序。
[IO.File]::WriteAllText((Join-Path $source 'AppleMusic.exe'),'fixture-exe-not-executable')
[IO.File]::WriteAllText((Join-Path $source 'AMPLibraryAgent.exe'),'fixture-agent-not-executable')
[IO.File]::WriteAllText((Join-Path $source '[Content_Types].xml'),'fixture-metadata')
$before=(Get-FileHash -LiteralPath (Join-Path $source 'AppxManifest.xml')).Hash
$out=Join-Path $workspace 'prepared'
$null=& (Join-Path $root 'scripts\prepare-package.ps1') -SourcePackage $source -Destination $out
$after=[IO.File]::ReadAllText((Join-Path $out 'AppxManifest.xml'))
if ($after -ne $text.Replace('MinVersion="10.0.19045.0"','MinVersion="10.0.19044.0"')) { throw 'FAIL: 非最小清单修改' }
if ((Get-FileHash -LiteralPath (Join-Path $source 'AppxManifest.xml')).Hash -ne $before) { throw 'FAIL: 修改了来源' }
if (-not (Test-Path -LiteralPath ($out+'.original-metadata\[Content_Types].xml'))) { throw 'FAIL: 元数据未隔离' }
$rejected=$false
try { $null=& (Join-Path $root 'scripts\prepare-package.ps1') -SourcePackage $source -Destination $out }
catch { $rejected=$true }
if (-not $rejected) { throw 'FAIL: 未拒绝现有目标目录' }
[IO.File]::WriteAllText((Join-Path $source 'AppxManifest.xml'),$text.Replace('Name="AppleInc.AppleMusicWin"','Name="AppleInc.AppleMusicWin.LTSC"'))
$rejected=$false
try { $null=& (Join-Path $root 'scripts\prepare-package.ps1') -SourcePackage $source -Destination (Join-Path $workspace 'bad-identity') }
catch { $rejected=$true }
if (-not $rejected -or (Test-Path -LiteralPath (Join-Path $workspace 'bad-identity'))) { throw 'FAIL: 错误身份未在复制前拒绝' }
Write-Host 'PASS: 清单只变更 MinVersion；来源不变；二进制哈希一致；签名元数据隔离；拒绝覆盖；拒绝 .LTSC。'
Write-Host "测试材料保留于：$workspace（未注册任何包、未关闭应用）。"
