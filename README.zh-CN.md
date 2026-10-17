# applemuisc2026-for-ltsc2021

将本次 Apple Music / Windows 10 Enterprise LTSC 2021 兼容排查整理成的脚本项目。名称按要求保留为 `applemuisc2026-for-ltsc2021`。

**非官方、单版本验证；不是 Apple Music 安装包，也不是订阅或 DRM 绕过工具。** 不附带 Apple EXE/DLL、账户数据、证书或原始诊断日志。

## 一键部署（新增）

**最简单：**解压本项目，把可信的 `1.1540.23041.0` **内部 x64 ZIP/APPX/MSIX** 放入 `payload` 目录，双击 `deploy.cmd`。没有放入时，窗口会让你粘贴安装文件/解压目录路径。若缺少 VCLibs，请把微软官方的两个 x64 框架 APPX 放入 `dependencies` 后重试。

也可在项目目录的 PowerShell 中只运行一行（参数里的路径换成你的文件）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy.ps1 -SourcePackage "D:\AppleMusic\MusicPackage_1.1540.23041.0_x64.zip"
```

此命令只对本次进程使用执行策略参数，不修改系统执行策略，不执行远程下载的代码。**没有托管的在线安装器，不提供虚构的 `irm | iex` 链接。**

管理员终端可以使用，但不是必需，也不会自动弹 UAC：安装仍属于**当前登录账户**。不要用 SYSTEM、任务计划服务账户或另一个管理员的凭据运行，否则不是为原桌面用户部署。

自动流程：系统/身份/路径预检 → 检查本地微软依赖 → 安全解压 → 创建独立副本与哈希验证 → 当前用户注册 → 创建不覆盖旧文件的桌面快捷方式 → 默认启动并检查进程。

- 支持文件名含空格和中文；拒绝路径穿越、重复路径、链接等危险 ZIP 条目。
- 只接受内部 x64 包；不接受外层 MSIXBUNDLE/APPXBUNDLE，不自动从第三方下载 Apple 包/依赖。
- 缺依赖、系统不符、应用未退出、已有安装时先停止，避免半途误覆盖。
- 缺失依赖仅从 `dependencies` 或 `-DependencyPath` 指定的本地 APPX/MSIX 安装，身份/版本/架构按原始清单匹配，由 Windows 验证签名。
- 注册已有安装须显式 `-ReplaceExisting`；不加参数不会动已有安装。
- 不启用开发者模式，不导入证书；系统策略禁止注册时停止并保留错误。

可选命令：

```powershell
# 无文件写入、无安装的预检；或将 -CheckOnly 换成 -WhatIf 看操作计划
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy.ps1 -SourcePackage "D:\AppleMusic\MusicPackage_1.1540.23041.0_x64.zip" -CheckOnly

# 确认替换现有安装，且部署后不启动
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy.ps1 -SourcePackage "D:\AppleMusic\MusicPackage_1.1540.23041.0_x64.zip" -ReplaceExisting -NoLaunch
```

部署记录保存在 `%LOCALAPPDATA%\applemuisc2026-for-ltsc2021\Deployments\`，成功后显示对应回滚命令。依赖是共享框架，失败/回滚时不自动移除已装依赖。准备/注册失败不删除账户；若注册后创建快捷方式失败，应用可能已注册，应查看记录再选择回滚。

一键入口已做模拟预检与安全解压测试，**未在全新电脑验证完整实际安装**。管理员权限不等于保证兼容、页面加载或 DRM 成功。

## 核心方案

1. 从可信原始解压目录独立复制程序，不使用硬链接，不修改来源。
2. 保留 `AppleInc.AppleMusicWin`、原始 Publisher、版本、依赖与所有扩展。
3. 仅将清单 `Windows.Desktop MinVersion` 从 `10.0.19045.0` 改为 `10.0.19044.0`。
4. 在新副本中隔离已失效的签名/包元数据，用当前用户开发模式注册。
5. 从原始 AUMID 启动；检查资料库代理及可选 COM 探测。

**不要把 Identity Name 改成 `.LTSC`。** 本次观察中，该身份会导致 AMP 后台初始化异常。普通缓存隔离不是主要修复方案，因此本项目不自动清理缓存，更不会清理登录/授权数据。

## 本次验证范围

| 项目 | 状态 |
|---|---|
| 系统 | Windows 10 Enterprise LTSC 2021，x64 / Build 19044 |
| Apple Music 包版本 | `1.1540.23041.0`，脚本固定此版本；不冒充支持未来版本 |
| 原始身份注册 | 本机状态 `Ok` |
| AppleMusic 与 AMPLibraryAgent | 本机原始身份目录运行且保持响应 |
| 资料库 COM | 此前探测成功；可用脚本重新检查 |
| 登录与授权 | 用户此前反馈成功；不导出、不复制凭据 |
| 主页、广播、详情页最终加载 | **尚待用户确认，不能视为全部页面已修复** |
| 新电脑全流程安装/DRM/下载/Store 更新 | 未验证，不作保证 |

## 文件结构

- `scripts/prepare-package.ps1`：构建全新副本，只修改目标系统最低版本，核对 EXE/DLL SHA256。
- `scripts/register-package.ps1`：校验清单、依赖与哈希，记录先前注册，默认拒绝替换现有安装。
- `scripts/unregister-package.ps1`：仅处理有匹配记录的本项目注册；恢复先前注册或保留数据注销。
- `scripts/create-shortcut.ps1`：创建原始身份快捷方式，不覆盖已有快捷方式。
- `scripts/verify-package.ps1`：只读检查已安装包；新项目副本可加 `-CheckBinaries`。
- `scripts/verify-library-agent.ps1`：核对进程所属目录；可选 `-Launch`、有超时的 `-ProbeCom`。
- `scripts/collect-diagnostics.ps1`：导出限定字段，避免采集账户令牌和原始 ETL。
- `templates/AppxManifest.xml`：本机工作清单参考，**不要拿它覆盖其他版本清单**。
- `tests/smoke-tests.ps1`：使用临时模拟文件测试复制/清单/拒绝覆盖逻辑，不注册模拟包。
- `docs/`：根因、风险、回滚与测试说明。
- `checksums/`：历史比对摘要及项目文件校验清单。

## 使用前

- 使用 **64 位 Windows PowerShell 5.1**；可从开始菜单打开“Windows PowerShell”，不要使用 PowerShell 7。
- 系统必须为 x64 Build 19044；不要通过伪造系统版本运行。
- 自行准备可信来源的 `1.1540.23041.0` x64 安装文件，解压到根目录含 `AppxManifest.xml`、`AppleMusic.exe`、`AMPLibraryAgent.exe` 的文件夹。
- 如果脚本被执行策略阻止，先审阅文件；确需使用时只对当前 PowerShell 进程调整，不更改全系统策略。域策略/管理员限制不由本项目绕过。
- 保持 VCLibs 原始依赖最低版本；缺失时只从 Microsoft 官方渠道安装，不降低清单中的依赖版本。
- 当前电脑已经能运行，无需为“保存项目”重新安装。阅读和打包不会更改现有注册。

## 准备、注册、验证

下面仅为运行示例；请在**项目所在目录**启动 Windows PowerShell。脚本参数中的安装文件路径应替换为自己的实际目录。

```powershell
# 指向解压后的目录，不是 ZIP，也不是现有账户数据目录
$Source = 'D:\AppleMusic\MusicPackage_1.1540.23041.0_x64_extracted'
$PackageRoot = .\scripts\prepare-package.ps1 -SourcePackage $Source

# 先看计划；随后退出 Apple Music，再实际注册
.\scripts\register-package.ps1 -PackageRoot $PackageRoot -WhatIf
.\scripts\register-package.ps1 -PackageRoot $PackageRoot

# 注册成功后操作
.\scripts\create-shortcut.ps1
.\scripts\verify-package.ps1 -CheckBinaries
.\scripts\verify-library-agent.ps1 -Launch -ProbeCom
```

准备脚本默认在 `%LOCALAPPDATA%\applemuisc2026-for-ltsc2021\Packages\` 下生成唯一目录。**不支持 `-Force`，不会删除/覆盖现有可用程序目录。** 元数据保存在同级 `.original-metadata` 目录，不含用户账户数据。

若已有同名原始身份安装，注册脚本默认停止。只有明确要替换、已备份必要资料并退出应用后，才使用：

```powershell
.\scripts\register-package.ps1 -PackageRoot $PackageRoot -ReplaceExisting
```

脚本保存旧清单位置并在注册失败时尝试恢复旧注册；这不是完整系统/资料库快照，不能保证恢复服务器状态或所有应用内设置。不要删除旧安装目录。

桌面快捷方式名称为 `Apple Music (LTSC 2021 Original Identity).lnk`，AUMID 由系统实际包族派生。不要直接运行解压目录的 EXE 代替包激活。

## 诊断与回滚

```powershell
.\scripts\collect-diagnostics.ps1

# 仅支持本项目新注册记录，不接管此前手工修复的安装
.\scripts\unregister-package.ps1 -PackageRoot $PackageRoot -WhatIf
.\scripts\unregister-package.ps1 -PackageRoot $PackageRoot
```

回滚需要退出应用并确认。存在旧注册时恢复它；无旧注册时，只对本项目匹配的开发模式包使用 `-PreserveApplicationData`。不删除程序目录、账户、Cookies 或授权文件。详见 `docs/rollback.md`。

## 风险与边界

降低安装声明不等于补齐新系统 API，也不保证所有功能兼容。开发模式注册可能要求系统已有相应许可；脚本不会修改开发者模式、组策略、证书或安全设置，失败时保留部署错误供检查。

不修改 DLL、hosts、代理、TLS/证书校验、StateRepository，不重新做 Publisher 实验，不升级 Windows。登录、订阅、页面内容、播放、下载和 DRM 仍取决于 Apple 服务与账户；Store 更新及未来版本均未保证兼容。

本项目于 2026-10-17 整理。分享前不要把本地日志、应用数据、原始安装包或快捷方式塞入发布包。