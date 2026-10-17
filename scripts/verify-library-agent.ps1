#requires -version 5.1
[CmdletBinding()]param([switch]$Launch,[switch]$ProbeCom)
. "$PSScriptRoot\common.ps1"
Assert-WindowsPowerShell
$p=Get-AppxPackage -Name $ExpectedName
if (-not $p) { throw '未找到原始身份包。' }
if ($Launch) {
    Start-Process (Join-Path $env:WINDIR 'explorer.exe') ('shell:AppsFolder\'+$p.PackageFamilyName+'!App')
    Start-Sleep -Seconds 8
}
$items=@(Get-Process AppleMusic,AMPLibraryAgent -ErrorAction SilentlyContinue)
foreach ($item in $items) {
    $path=$item.Path
    [pscustomobject]@{Id=$item.Id; Process=$item.ProcessName; Responding=$item.Responding;
        FromOriginalPackage=($path -and $path.StartsWith($p.InstallLocation.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)); Path=$path}
}
if (-not @($items | Where-Object { $_.ProcessName -eq 'AMPLibraryAgent' }).Count) {
    Write-Warning '尚未检测到 AMPLibraryAgent；这不等于已确认页面故障。可打开应用再检查。'
}
if ($ProbeCom) {
    # 独立 STA PowerShell 子进程：超时只终止本次检查，不影响应用进程。
    $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $helper=Join-Path $PSScriptRoot 'probe-library-com.ps1'
    $output=Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N')+'.txt')
    $errors=$output+'.err'
    $child=$null
    try {
        $child=Start-Process -FilePath $exe -ArgumentList @('-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',('"'+$helper+'"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput $output -RedirectStandardError $errors
        if (-not $child.WaitForExit(25000)) {
            $child.Kill()
            Write-Warning 'COM 检查超过 25 秒；只终止探测子进程。页面结果仍需人工确认。'
        } else {
            $child.WaitForExit()
            if (Test-Path -LiteralPath $output) { Get-Content -LiteralPath $output }
            if ($child.ExitCode -ne 0) { Write-Warning 'COM 探测失败；不代表所有网络功能不可用。' }
        }
    } finally {
        if ($child) { $child.Dispose() }
        foreach ($file in @($output,$errors)) { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file } }
    }
}