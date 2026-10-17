#requires -version 5.1
# Dot-source common.ps1 first. These helpers do not change registrations.
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Read-ArchiveManifest([string]$ArchivePath) {
    $archive=[IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $entries=@($archive.Entries | Where-Object { $_.FullName -ieq 'AppxManifest.xml' })
        if ($entries.Count -ne 1) { throw '压缩包根目录必须有唯一 AppxManifest.xml；不接受外层 bundle。请提供内部 x64 包。' }
        if ($entries[0].Length -gt 2MB) { throw '压缩包清单过大。' }
        $doc=New-Object Xml.XmlDocument
        $doc.XmlResolver=$null
        $settings=New-Object Xml.XmlReaderSettings
        $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit
        $settings.MaxCharactersInDocument=2MB
        $stream=$entries[0].Open()
        $reader=[Xml.XmlReader]::Create($stream,$settings)
        try { $doc.Load($reader) } finally { $reader.Dispose();$stream.Dispose() }
        return ,$doc
    } finally { $archive.Dispose() }
}
function Get-MusicSource([string]$Source) {
    $path=(Resolve-Path -LiteralPath $Source).Path
    $item=Get-Item -LiteralPath $path -Force
    if ($item.PSIsContainer) {
        Assert-NoReparsePoints $path
        $m=Get-SafeManifest (Join-Path $path 'AppxManifest.xml')
        foreach ($name in @('AppleMusic.exe','AMPLibraryAgent.exe')) {
            if (-not (Test-Path -LiteralPath (Join-Path $path $name) -PathType Leaf)) { throw "来源缺少 $name" }
        }
        return [pscustomobject]@{Path=$path; IsArchive=$false; Document=$m.Document; Namespace=$m.Namespace}
    }
    if ($item.Extension -notin @('.zip','.appx','.msix')) { throw '只支持解压目录或内部 x64 .zip/.appx/.msix 包，不接受 bundle/下载链接。' }
    $doc=Read-ArchiveManifest $path
    $ns=New-Object Xml.XmlNamespaceManager($doc.NameTable)
    $ns.AddNamespace('f','http://schemas.microsoft.com/appx/manifest/foundation/windows10')
    $id=$doc.SelectSingleNode('/f:Package/f:Identity',$ns)
    $targets=@($doc.SelectNodes('/f:Package/f:Dependencies/f:TargetDeviceFamily',$ns))
    if (-not $id -or $id.GetAttribute('Name') -ne $ExpectedName -or
        $id.GetAttribute('Publisher') -ne $ExpectedPublisher -or
        $id.GetAttribute('Version') -ne $ExpectedVersion -or
        $id.GetAttribute('ProcessorArchitecture') -ne 'x64' -or $targets.Count -ne 1 -or
        $targets[0].GetAttribute('Name') -ne 'Windows.Desktop' -or
        $targets[0].GetAttribute('MinVersion') -notin @('10.0.19044.0','10.0.19045.0')) {
        throw '压缩包身份、版本、架构或最低系统版本不符。'
    }
    return [pscustomobject]@{Path=$path; IsArchive=$true; Document=$doc; Namespace=$ns}
}
function Get-SafeArchiveEntries($Archive,[string]$Destination) {
    $Destination=[IO.Path]::GetFullPath($Destination)
    $prefix=[IO.Path]::GetFullPath($Destination).TrimEnd('\')+'\'
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $total=[long]0
    if ($Archive.Entries.Count -gt 100000) { throw '压缩包条目数超过安全限制。' }
    $result=@()
    foreach ($entry in $Archive.Entries) {
        $relative=$entry.FullName.Replace('/','\')
        if (-not $relative -or $relative.StartsWith('\') -or $relative.Contains(':')) { throw '压缩包含绝对路径/ADS。' }
        $parts=$relative.TrimEnd('\').Split('\')
        foreach ($part in $parts) {
            if (-not $part -or $part -in @('.','..') -or $part.TrimEnd(' ','.') -ne $part -or
                $part.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
                $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw "压缩包路径不安全：$relative" }
        }
        $path=[IO.Path]::GetFullPath((Join-Path $Destination $relative))
        if (-not $path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or -not $seen.Add($path)) {
            throw "压缩包路径越界或大小写重复：$relative"
        }
        if (($entry.ExternalAttributes -band 0x400) -ne 0 -or
            (($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw '压缩包含联接点/符号链接。' }
        $total+=$entry.Length
        if ($total -gt 4GB) { throw '解压体积超过 4 GB 安全限制。' }
        $result += [pscustomobject]@{Entry=$entry; Path=$path; Directory=$relative.EndsWith('\')}
    }
    foreach ($required in @('AppxManifest.xml','AppleMusic.exe','AMPLibraryAgent.exe')) {
        $found=@($result | Where-Object { $_.Path -ieq (Join-Path $Destination $required) -and -not $_.Directory })
        if ($found.Count -ne 1) { throw "压缩包缺少根目录文件：$required" }
    }
    return $result
}
function Expand-MusicArchive([string]$ArchivePath,[string]$Destination) {
    if (Test-Path -LiteralPath $Destination) { throw '解压目标已存在，拒绝覆盖。' }
    $archive=[IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        # 在写入任何条目前，先检查全部路径。
        $entries=@(Get-SafeArchiveEntries $archive $Destination)
        New-Item -ItemType Directory -Path $Destination | Out-Null
        foreach ($item in $entries) {
            if ($item.Directory) { New-Item -ItemType Directory -Path $item.Path -Force | Out-Null; continue }
            New-Item -ItemType Directory -Path (Split-Path -Parent $item.Path) -Force | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($item.Entry,$item.Path,$false)
        }
    } finally { $archive.Dispose() }
}
function Get-MissingMusicDependencies($SourceInfo) {
    $missing=@()
    foreach ($dep in $SourceInfo.Document.SelectNodes('/f:Package/f:Dependencies/f:PackageDependency',$SourceInfo.Namespace)) {
        $matches=@(Get-AppxPackage -Name $dep.GetAttribute('Name') | Where-Object {
            [version]$_.Version -ge [version]$dep.GetAttribute('MinVersion') -and
            $_.Publisher -eq $dep.GetAttribute('Publisher') -and $_.Architecture -in @('X64','Neutral') })
        if (-not $matches.Count) { $missing+=$dep }
    }
    return $missing
}
function Get-DependencyInstallPlan($SourceInfo,[string[]]$DependencyPaths) {
    $required=@($SourceInfo.Document.SelectNodes('/f:Package/f:Dependencies/f:PackageDependency',$SourceInfo.Namespace))
    $candidates=@()
    foreach ($path in $DependencyPaths) {
        $full=(Resolve-Path -LiteralPath $path).Path
        if ([IO.Path]::GetExtension($full) -notin @('.appx','.msix')) { throw '依赖文件必须为 .appx/.msix；不要放入 EXE 或 ZIP。' }
        $doc=Read-ArchiveManifest $full
        $ns=New-Object Xml.XmlNamespaceManager($doc.NameTable)
        $ns.AddNamespace('f','http://schemas.microsoft.com/appx/manifest/foundation/windows10')
        $id=$doc.SelectSingleNode('/f:Package/f:Identity',$ns)
        $framework=$doc.SelectSingleNode('/f:Package/f:Properties/f:Framework',$ns)
        if (-not $id -or -not $framework -or $framework.InnerText -ne 'true') { throw '依赖不是框架包。' }
        $matches=@($required | Where-Object { $_.GetAttribute('Name') -eq $id.GetAttribute('Name') -and
            $_.GetAttribute('Publisher') -eq $id.GetAttribute('Publisher') -and
            [version]$id.GetAttribute('Version') -ge [version]$_.GetAttribute('MinVersion') })
        if ($matches.Count -ne 1 -or $id.GetAttribute('ProcessorArchitecture') -notin @('x64','neutral')) {
            throw "依赖名称/Publisher/版本/架构不符合原始清单：$full"
        }
        $targets=@($doc.SelectNodes('/f:Package/f:Dependencies/f:TargetDeviceFamily',$ns))
        if (-not @($targets | Where-Object { $_.GetAttribute('Name') -in @('Windows.Desktop','Windows.Universal') -and
            [version]$_.GetAttribute('MinVersion') -le [version]'10.0.19044.0' }).Count) { throw "依赖不声明支持 19044：$full" }
        $candidates += [pscustomobject]@{Name=$id.GetAttribute('Name'); Version=[version]$id.GetAttribute('Version'); Path=$full}
    }
    $plan=@()
    foreach ($dep in @(Get-MissingMusicDependencies $SourceInfo)) {
        $candidate=$candidates | Where-Object {$_.Name -eq $dep.GetAttribute('Name')} | Sort-Object Version -Descending | Select-Object -First 1
        if (-not $candidate) { throw "缺少 $($dep.GetAttribute('Name')) >= $($dep.GetAttribute('MinVersion'))。请提供微软官方签名 x64 依赖 .appx 到 dependencies 目录，再运行。不会自动从第三方网站下载。" }
        $plan+=$candidate
    }
    return $plan
}