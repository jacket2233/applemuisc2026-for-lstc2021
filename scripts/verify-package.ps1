#requires -version 5.1
[CmdletBinding()]param([switch]$CheckBinaries)
. "$PSScriptRoot\common.ps1"
Assert-WindowsPowerShell
$p=Get-AppxPackage -Name $ExpectedName
if (-not $p) { throw '未找到原始身份包。' }
$m=Get-SafeManifest (Join-Path $p.InstallLocation 'AppxManifest.xml') -Prepared
if ("$($p.Status)" -ne 'Ok') { throw "包状态异常：$($p.Status)" }
if ($CheckBinaries) {
    $r=Get-Receipt $p.InstallLocation
    Assert-BinaryInventory $p.InstallLocation $r
}
[pscustomobject]@{Name=$p.Name; Version=$p.Version.ToString(); Status="$($p.Status)";
    PackageFamilyName=$p.PackageFamilyName; InstallLocation=$p.InstallLocation;
    Publisher=$m.Identity.GetAttribute('Publisher'); MinVersion=$m.Target.GetAttribute('MinVersion');
    BinaryHashesChecked=[bool]$CheckBinaries }