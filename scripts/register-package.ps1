#requires -version 5.1
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
param([Parameter(Mandatory=$true)][string]$PackageRoot, [switch]$ReplaceExisting)
. "$PSScriptRoot\common.ps1"
Assert-WindowsPowerShell
Assert-HostBuild
$root = (Resolve-Path -LiteralPath $PackageRoot).Path
$r = Get-Receipt $root
$manifest = Join-Path $root 'AppxManifest.xml'
$m = Get-SafeManifest $manifest -Prepared
if ((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash -ne $r.ManifestSHA256) { throw '清单自准备后被修改。' }
Assert-BinaryInventory $root $r
$current = @(Get-AppxPackage -Name $ExpectedName)
if ($current.Count -gt 1) { throw '存在多个同名包，请人工检查。' }
$previous = $null
if ($current.Count) {
    if ($current[0].InstallLocation.TrimEnd('\') -eq $root.TrimEnd('\')) { Write-Host '相同目录已注册；未重新注册。'; return }
    if (-not $ReplaceExisting) { throw '发现现有原始身份安装。默认不替换；确认后显式添加 -ReplaceExisting。' }
    $previous = [ordered]@{ PackageFullName=$current[0].PackageFullName; InstallLocation=$current[0].InstallLocation;
        IsDevelopmentMode=[bool]$current[0].IsDevelopmentMode }
}
foreach ($dep in $m.Document.SelectNodes('/f:Package/f:Dependencies/f:PackageDependency',$m.Namespace)) {
    $matches = @(Get-AppxPackage -Name $dep.GetAttribute('Name') | Where-Object {
        [version]$_.Version -ge [version]$dep.GetAttribute('MinVersion') -and
        $_.Publisher -eq $dep.GetAttribute('Publisher') -and $_.Architecture -in @('X64','Neutral') })
    if (-not $matches.Count) { throw "缺少依赖：$($dep.GetAttribute('Name')) >= $($dep.GetAttribute('MinVersion'))。请从 Microsoft 官方渠道安装；不会降低依赖版本。" }
}
if (-not $PSCmdlet.ShouldProcess($root,'当前用户注册 Apple Music；应用须预先退出')) { return }
if (@(Get-Process AppleMusic,AMPLibraryAgent -ErrorAction SilentlyContinue).Count) { throw '请先从 Apple Music 界面退出应用。脚本不会强制结束进程。' }
$state = [ordered]@{ Project='applemuisc2026-for-ltsc2021'; PackageRoot=$root; Previous=$previous;
    Registered=$false; Started=(Get-Date -Format o) }
$statePath = Join-Path $root 'ltsc-registration.json'
Save-Json $state $statePath
try {
    Add-AppxPackage -Register $manifest -ErrorAction Stop
    $installed = Get-AppxPackage -Name $ExpectedName
    if (-not $installed -or $installed.InstallLocation.TrimEnd('\') -ne $root.TrimEnd('\') -or "$($installed.Status)" -ne 'Ok') {
        throw '注册后的目录/状态未通过验证。'
    }
    $state.Registered=$true
    Save-Json $state $statePath
    $installed | Select-Object Name,PackageFullName,Status,InstallLocation
} catch {
    $reason = $_
    if ($previous) {
        try { Add-AppxPackage -Register (Join-Path $previous.InstallLocation 'AppxManifest.xml') -ErrorAction Stop }
        catch { Write-Warning "自动恢复旧清单失败：$($_.Exception.Message)。未删除应用数据，请使用原安装来源恢复。" }
    }
    throw $reason
}