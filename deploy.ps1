#requires -version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Position=0)][string]$SourcePackage,
    [string[]]$DependencyPath,
    [switch]$ReplaceExisting,
    [switch]$NoLaunch,
    [switch]$CheckOnly
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\scripts\common.ps1"
. "$PSScriptRoot\scripts\deployment-common.ps1"
try {
    Assert-WindowsPowerShell
    Assert-HostBuild
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($sid -in @('S-1-5-18','S-1-5-19','S-1-5-20')) { throw '不要用 SYSTEM/服务账户部署；请使用实际桌面用户。' }
    Write-Host ('部署用户：'+[Security.Principal.WindowsIdentity]::GetCurrent().Name)
    Write-Host '管理员权限可用，但注册仍只属于当前账户；不要输入另一个管理员的凭据来替换用户。'
    if (-not $SourcePackage) {
        $default=Join-Path $PSScriptRoot 'payload'
        $files=@(Get-ChildItem -LiteralPath $default -File | Where-Object {$_.Extension -in @('.zip','.appx','.msix')})
        if (Test-Path -LiteralPath (Join-Path $default 'AppxManifest.xml')) { $SourcePackage=$default }
        elseif ($files.Count -eq 1) { $SourcePackage=$files[0].FullName }
        elseif ($CheckOnly -or $WhatIfPreference) { throw '请用 -SourcePackage 指定目录或内部 x64 包，或放入 payload。' }
        else {
            $SourcePackage=Read-Host '请粘贴解压目录或内部 x64 ZIP/APPX/MSIX 的完整路径'
            $SourcePackage=$SourcePackage.Trim().Trim('"')
        }
    }
    if (-not $SourcePackage) { throw '未提供 Apple Music 安装文件。' }
    $source=Get-MusicSource $SourcePackage
    if ($source.IsArchive) {
        $archive=[IO.Compression.ZipFile]::OpenRead($source.Path)
        try { $null=Get-SafeArchiveEntries $archive (Join-Path $env:TEMP ('music-preflight-'+[guid]::NewGuid().ToString('N'))) }
        finally { $archive.Dispose() }
    }
    $current=@(Get-AppxPackage -Name $ExpectedName)
    if ($current.Count -gt 1) { throw '存在多个同名原始身份包，请人工检查。' }
    if ($current.Count -and -not $ReplaceExisting) { throw '检测到现有 Apple Music，已保留。确定替换时使用 -ReplaceExisting；不是默认行为。' }
    $running=@(Get-Process AppleMusic,AMPLibraryAgent -ErrorAction SilentlyContinue)
    if ($running.Count) { throw '请先从界面退出 Apple Music，再运行一键部署；不会强制结束进程。' }
    if (-not $DependencyPath) {
        $DependencyPath=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'dependencies') -File |
            Where-Object {$_.Extension -in @('.appx','.msix')} | ForEach-Object {$_.FullName})
    }
    $plan=@(Get-DependencyInstallPlan $source $DependencyPath)
    Write-Host ('来源：'+$source.Path)
    Write-Host ('需要安装的本地微软依赖数：'+$plan.Count)
    if ($CheckOnly) { Write-Host '预检通过；未写文件、安装依赖或更改注册。'; return }
    if (-not $PSCmdlet.ShouldProcess($source.Path,'一键部署：依赖 → 新副本 → 当前用户注册 → 快捷方式')) { return }
    $runId=(Get-Date -Format yyyyMMdd-HHmmss)+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $base=Join-Path $env:LOCALAPPDATA 'applemuisc2026-for-ltsc2021'
    $logDir=Join-Path $base ('Deployments\'+$runId)
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $state=[ordered]@{Project='applemuisc2026-for-ltsc2021';Started=(Get-Date -Format o);
        UserSid=$sid;Source=$source.Path;PackageRoot=$null;Stage='Preflight';Error=$null;DependenciesInstalled=@();Completed=$false}
    $statePath=Join-Path $logDir 'deployment.json'
    Save-Json $state $statePath
    try {
        foreach ($dep in $plan) {
            Write-Host ('安装官方依赖：'+$dep.Name)
            # 由 Windows 部署服务验证签名；不降低依赖版本、不导入证书。
            Add-AppxPackage -Path $dep.Path -ErrorAction Stop
            $state.DependenciesInstalled+=@($dep.Name)
            Save-Json $state $statePath
        }
        if (@(Get-MissingMusicDependencies $source).Count) { throw '依赖安装后仍未满足要求，未注册 Apple Music。' }
        $state.Stage='Prepare'
        Save-Json $state $statePath
        $inputDirectory=$source.Path
        if ($source.IsArchive) {
            $inputDirectory=Join-Path $base ('Sources\'+$runId)
            Expand-MusicArchive $source.Path $inputDirectory
        }
        $prepared=& "$PSScriptRoot\scripts\prepare-package.ps1" -SourcePackage $inputDirectory
        $state.PackageRoot=[string]$prepared
        $state.Stage='Register'
        Save-Json $state $statePath
        $null=& "$PSScriptRoot\scripts\register-package.ps1" -PackageRoot $prepared -ReplaceExisting:$ReplaceExisting
        $state.Stage='Verify'
        Save-Json $state $statePath
        & "$PSScriptRoot\scripts\verify-package.ps1" -CheckBinaries | Format-List | Out-Host
        $shortcut=Join-Path ([Environment]::GetFolderPath('Desktop')) 'Apple Music (LTSC 2021 Original Identity).lnk'
        if (Test-Path -LiteralPath $shortcut) {
            $shortcut=Join-Path ([Environment]::GetFolderPath('Desktop')) ('Apple Music (LTSC 2021 '+$runId+').lnk')
        }
        & "$PSScriptRoot\scripts\create-shortcut.ps1" -ShortcutPath $shortcut
        $state.Stage='Complete'
        $state.Completed=$true
        Save-Json $state $statePath
        Write-Host '部署完成。页面加载、登录、订阅、播放仍需使用者验证。'
        Write-Host ('部署记录：'+$statePath)
        Write-Host ('回滚：& "'+$PSScriptRoot+'\scripts\unregister-package.ps1" -PackageRoot "'+$prepared+'"')
        if (-not $NoLaunch) {
            try { & "$PSScriptRoot\scripts\verify-library-agent.ps1" -Launch | Format-List | Out-Host }
            catch { Write-Warning ('注册已完成，但启动/进程检查未通过：'+$_.Exception.Message) }
        }
    } catch {
        $state.Error=$_.Exception.Message
        Save-Json $state $statePath
        Write-Warning ('已停止后续步骤，记录：'+$statePath+'。不会清除账户或自动卸载共享依赖。')
        throw
    }
} catch {
    Write-Error ('一键部署未完成：'+$_.Exception.Message) -ErrorAction Continue
    exit 1
}