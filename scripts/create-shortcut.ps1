#requires -version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param([string]$ShortcutPath=(Join-Path ([Environment]::GetFolderPath('Desktop')) 'Apple Music (LTSC 2021 Original Identity).lnk'))
. "$PSScriptRoot\common.ps1"
Assert-WindowsPowerShell
$p=Get-AppxPackage -Name $ExpectedName
if (-not $p) { throw '未找到原始身份包。' }
$null=Get-SafeManifest (Join-Path $p.InstallLocation 'AppxManifest.xml') -Prepared
$ShortcutPath=[IO.Path]::GetFullPath($ShortcutPath)
if ([IO.Path]::GetExtension($ShortcutPath) -ne '.lnk') { throw '目标必须为 .lnk 文件。' }
if (Test-Path -LiteralPath $ShortcutPath) { throw '快捷方式已存在；请选择其他名称，不自动覆盖。' }
if ($PSCmdlet.ShouldProcess($ShortcutPath,'创建原始身份快捷方式')) {
    $ws=New-Object -ComObject WScript.Shell
    try {
        $s=$ws.CreateShortcut($ShortcutPath)
        $s.TargetPath=Join-Path $env:WINDIR 'explorer.exe'
        $s.Arguments='shell:AppsFolder\'+$p.PackageFamilyName+'!App'
        $s.WorkingDirectory=$p.InstallLocation
        $s.Description='Apple Music / original package identity / LTSC 2021'
        $s.Save()
    } finally { if ($ws) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ws) } }
    Write-Host "快捷方式：$ShortcutPath"
}