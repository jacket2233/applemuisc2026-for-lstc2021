#requires -version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourcePackage, [string]$Destination)
. "$PSScriptRoot\common.ps1"
Assert-WindowsPowerShell
Assert-HostBuild
$source = (Resolve-Path -LiteralPath $SourcePackage).Path.TrimEnd('\')
if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw '请先解压 ZIP，传入包含 AppxManifest.xml 的目录。' }
Assert-NoReparsePoints $source
$m = Get-SafeManifest (Join-Path $source 'AppxManifest.xml')
foreach ($exe in @('AppleMusic.exe','AMPLibraryAgent.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $exe) -PathType Leaf)) { throw "来源不完整：缺少 $exe" }
}
if (-not $Destination) {
    $Destination = Join-Path $env:LOCALAPPDATA ('applemuisc2026-for-ltsc2021\Packages\' +
        $ExpectedVersion + '-' + (Get-Date -Format yyyyMMdd-HHmmss) + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
}
$destinationFull = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
if (Test-Path -LiteralPath $destinationFull) { throw '目标目录已经存在。为保护可用安装，本项目不支持覆盖或 -Force。请选择全新目录。' }
if ($destinationFull.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)) { throw '目标不能位于来源内部。' }
$packageBase = Join-Path $env:LOCALAPPDATA 'Packages'
if ($destinationFull -eq $packageBase -or $destinationFull.StartsWith($packageBase+'\',[StringComparison]::OrdinalIgnoreCase)) {
    throw '不能把程序文件写入 Windows 应用数据目录。'
}
New-Item -ItemType Directory -Path $destinationFull | Out-Null
# 逐项使用 LiteralPath；不把通配符传给 LiteralPath，也不使用硬链接。
Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
    if ($_.Name -eq 'ltsc-project-receipt.json') { throw '来源包含旧项目记录，请使用原始包。' }
    Copy-Item -LiteralPath $_.FullName -Destination $destinationFull -Recurse -Force
}
$outManifest = Join-Path $destinationFull 'AppxManifest.xml'
$original = [IO.File]::ReadAllText($outManifest)
$pattern = '(<TargetDeviceFamily\b[^>]*\bName="Windows\.Desktop"[^>]*\bMinVersion=")10\.0\.19045\.0(")'
$changed = [regex]::Replace($original, $pattern, '${1}10.0.19044.0${2}')
if ($m.Target.GetAttribute('MinVersion') -eq '10.0.19045.0' -and $changed -eq $original) {
    throw '清单格式未匹配；保留副本供检查，未注册。'
}
[IO.File]::WriteAllText($outManifest, $changed, (New-Object Text.UTF8Encoding($false)))
$null = Get-SafeManifest $outManifest -Prepared
# 签名元数据不再适用于修改后的清单；仅在新副本中隔离，绝不触碰源文件。
$metadata = $destinationFull + '.original-metadata'
if (Test-Path -LiteralPath $metadata) { throw '元数据备份目标已存在。' }
New-Item -ItemType Directory -Path $metadata | Out-Null
foreach ($name in @('AppxSignature.p7x','AppxBlockMap.xml','[Content_Types].xml','AppxMetadata')) {
    $item = Join-Path $destinationFull $name
    if (Test-Path -LiteralPath $item) { Move-Item -LiteralPath $item -Destination $metadata }
}
$inventory = @()
$prefix = $source + '\'
foreach ($file in @(Get-ChildItem -LiteralPath $source -Recurse -File | Where-Object { $_.Extension -in @('.dll','.exe') })) {
    $relative = $file.FullName.Substring($prefix.Length)
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath (Join-Path $destinationFull $relative) -Algorithm SHA256).Hash -ne $hash) {
        throw "复制校验失败：$relative；未注册。"
    }
    $inventory += [pscustomobject]@{Path=$relative; SHA256=$hash}
}
$receipt = [ordered]@{ Project='applemuisc2026-for-ltsc2021'; Created=(Get-Date -Format o);
    PackageRoot=$destinationFull; Source=$source; MetadataBackup=$metadata;
    ManifestSHA256=(Get-FileHash -LiteralPath $outManifest -Algorithm SHA256).Hash;
    BinaryCount=$inventory.Count; Binaries=$inventory }
Save-Json $receipt (Join-Path $destinationFull 'ltsc-project-receipt.json')
Write-Host "准备完成；未注册、未关闭应用。已校验 $($inventory.Count) 个 EXE/DLL。"
Write-Host "PackageRoot：$destinationFull"
Write-Output $destinationFull