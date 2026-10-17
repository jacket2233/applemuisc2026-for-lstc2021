#requires -version 5.1
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param([Parameter(Mandatory=$true)][string]$PackageRoot)
. "$PSScriptRoot\common.ps1"
Assert-WindowsPowerShell
$root=(Resolve-Path -LiteralPath $PackageRoot).Path
$null=Get-Receipt $root
$path=Join-Path $root 'ltsc-registration.json'
if (-not (Test-Path -LiteralPath $path)) { throw '没有本项目注册记录，拒绝移除现有应用。' }
$state=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $state.Registered -or $state.PackageRoot -ne $root) { throw '注册记录不匹配或已经回滚。' }
$p=Get-AppxPackage -Name $ExpectedName
if (-not $p) { Write-Host '未找到注册；保留文件。'; return }
if ($p.InstallLocation.TrimEnd('\') -ne $root.TrimEnd('\') -or -not $p.IsDevelopmentMode) {
    throw '当前包不是此项目的开发模式注册；拒绝移除。'
}
if (-not $PSCmdlet.ShouldProcess($p.PackageFullName,'恢复先前注册，或保留数据移除本次注册')) { return }
if (@(Get-Process AppleMusic,AMPLibraryAgent -ErrorAction SilentlyContinue).Count) { throw '请先从界面退出 Apple Music。' }
if ($state.Previous) {
    $previousManifest=Join-Path $state.Previous.InstallLocation 'AppxManifest.xml'
    if (-not (Test-Path -LiteralPath $previousManifest)) { throw '先前清单已不存在。未移除任何注册。' }
    Add-AppxPackage -Register $previousManifest -ErrorAction Stop
} else {
    Remove-AppxPackage -Package $p.PackageFullName -PreserveApplicationData -ErrorAction Stop
}
$state.Registered=$false
Save-Json $state $path
Write-Host '回滚完成。未删除程序目录、账户、授权或缓存。'