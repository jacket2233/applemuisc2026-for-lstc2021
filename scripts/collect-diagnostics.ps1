#requires -version 5.1
[CmdletBinding()]param([string]$OutputDirectory=(Join-Path $PSScriptRoot '..\logs'))
. "$PSScriptRoot\common.ps1"
Assert-WindowsPowerShell
$directory=Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ((Get-Date -Format yyyyMMdd-HHmmss)+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path $directory -Force | Out-Null
function Hide-LocalPath($value) {
    if ($null -eq $value) { return $null }
    ([string]$value).Replace($env:USERPROFILE,'%USERPROFILE%')
}
$os=Get-CimInstance Win32_OperatingSystem
Save-Json ([ordered]@{Caption=$os.Caption; Build=$os.BuildNumber; Architecture=$os.OSArchitecture}) (Join-Path $directory 'os.json')
$packages=@(Get-AppxPackage -Name 'AppleInc.AppleMusicWin*' | ForEach-Object {
    [pscustomobject]@{Name=$_.Name; Version=$_.Version.ToString(); Status="$($_.Status)";
        PackageFullName=$_.PackageFullName; IsDevelopmentMode=$_.IsDevelopmentMode;
        InstallLocation=(Hide-LocalPath $_.InstallLocation)} })
Save-Json $packages (Join-Path $directory 'packages.json')
$processes=@(Get-Process AppleMusic,AMPLibraryAgent -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{Name=$_.ProcessName; Id=$_.Id; Responding=$_.Responding; Path=(Hide-LocalPath $_.Path)} })
Save-Json $processes (Join-Path $directory 'processes.json')
$events=@()
try {
    $recent=Get-WinEvent -FilterHashtable @{LogName='Application';Id=1000;StartTime=(Get-Date).AddHours(-2)} -MaxEvents 100 -ErrorAction Stop
    foreach ($e in $recent) {
        [xml]$xml=$e.ToXml()
        $data=@{}
        foreach ($node in $xml.Event.EventData.Data) { $data[$node.GetAttribute('Name')]=$node.InnerText }
        if ($data['AppName'] -notin @('AppleMusic.exe','AMPLibraryAgent.exe')) { continue }
        $events += [pscustomobject]@{Time=$e.TimeCreated.ToString('o'); Id=$e.Id;
            App=$data['AppName']; Module=$data['ModuleName']; ExceptionCode=$data['ExceptionCode']}
    }
} catch { Write-Warning '未读取到相关崩溃事件，或事件日志不可用。' }
Save-Json $events (Join-Path $directory 'crashes.json')
Write-Host "诊断完成：$directory"
Write-Host '未导出原始日志、令牌、账户、Cookies 或授权。分享前仍请检查文件。'