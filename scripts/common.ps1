#requires -version 5.1
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ExpectedName = 'AppleInc.AppleMusicWin'
$ExpectedPublisher = 'CN=5BD5593D-A41B-4F89-884E-B4F3E0FBAA75'
$ExpectedVersion = '1.1540.23041.0'
function Assert-WindowsPowerShell {
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess) {
        throw '请使用 64 位 Windows PowerShell 5.1，而不是 PowerShell 7。'
    }
}
function Assert-HostBuild {
    $build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
    if ($build -ne 19044 -or -not [Environment]::Is64BitOperatingSystem) {
        throw "本项目仅验证了 x64 Windows Build 19044；当前 Build：$build。"
    }
}
function Get-SafeManifest([string]$Path, [switch]$Prepared) {
    $doc = New-Object Xml.XmlDocument
    $doc.PreserveWhitespace = $true
    $doc.XmlResolver = $null
    $settings = New-Object Xml.XmlReaderSettings
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $reader = [Xml.XmlReader]::Create($Path, $settings)
    try { $doc.Load($reader) } finally { $reader.Dispose() }
    $ns = New-Object Xml.XmlNamespaceManager($doc.NameTable)
    $ns.AddNamespace('f','http://schemas.microsoft.com/appx/manifest/foundation/windows10')
    $id = $doc.SelectSingleNode('/f:Package/f:Identity', $ns)
    $families = @($doc.SelectNodes('/f:Package/f:Dependencies/f:TargetDeviceFamily', $ns))
    if (-not $id -or $families.Count -ne 1) { throw '清单缺少唯一的目标系统或身份。' }
    $target = $families[0]
    if ($id.GetAttribute('Name') -ne $ExpectedName -or
        $id.GetAttribute('Publisher') -ne $ExpectedPublisher -or
        $id.GetAttribute('Version') -ne $ExpectedVersion -or
        $id.GetAttribute('ProcessorArchitecture') -ne 'x64' -or
        $target.GetAttribute('Name') -ne 'Windows.Desktop') {
        throw '清单不是本项目验证过的 Apple 原始身份/x64/版本；未继续。'
    }
    $min = $target.GetAttribute('MinVersion')
    if ($min -notin @('10.0.19044.0','10.0.19045.0') -or
        ($Prepared -and $min -ne '10.0.19044.0')) { throw "不支持的 MinVersion：$min" }
    [pscustomobject]@{ Document=$doc; Identity=$id; Target=$target; Namespace=$ns }
}
function Assert-NoReparsePoints([string]$Root) {
    $item = Get-Item -LiteralPath $Root -Force
    $all = @($item) + @(Get-ChildItem -LiteralPath $Root -Recurse -Force)
    if (@($all | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) {
        throw '来源含符号链接/联接点，拒绝递归复制。请使用正常解压目录。'
    }
}
function Save-Json($Object, [string]$Path) {
    ConvertTo-Json -InputObject $Object -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}
function Get-Receipt([string]$PackageRoot) {
    $path = Join-Path $PackageRoot 'ltsc-project-receipt.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw '缺少项目准备记录；不能接管其他安装。' }
    $r = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($r.Project -ne 'applemuisc2026-for-ltsc2021' -or
        [IO.Path]::GetFullPath($r.PackageRoot).TrimEnd('\') -ne [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\')) {
        throw '项目记录与包目录不匹配。'
    }
    $r
}
function Assert-BinaryInventory([string]$PackageRoot, $Receipt) {
    $binaries = @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.dll','.exe') })
    if ($binaries.Count -ne @($Receipt.Binaries).Count) { throw '二进制文件数量与准备记录不符。' }
    $prefix = [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\') + '\'
    foreach ($entry in $Receipt.Binaries) {
        $path = [IO.Path]::GetFullPath((Join-Path $PackageRoot $entry.Path))
        if (-not $path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw '记录含越界路径。' }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.SHA256) {
            throw "二进制文件缺失或被修改：$($entry.Path)"
        }
    }
}