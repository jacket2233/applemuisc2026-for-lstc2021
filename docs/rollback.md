# 安全回滚

1. 此项目不会接管已存在的手工修复目录。准备包生成新的唯一目录，注册生成 `ltsc-registration.json`。
2. `register-package.ps1` 默认拒绝替换其他目录；`-ReplaceExisting` 才允许记录旧位置后替换。
3. 注销脚本必须传入准确 `-PackageRoot`，并检查项目准备记录、注册记录、当前 InstallLocation 和开发模式状态。记录不符就停止。
4. 有旧注册：在不主动卸载当前包的情况下重新注册旧 `AppxManifest.xml`。旧目录必须仍存在。失败时停止，不尝试删除数据。
5. 无旧注册：仅注销本项目匹配的开发模式包，并指定 `-PreserveApplicationData`。此参数不应被当作适用于所有 Store 包的数据备份方案。
6. 两个操作都支持 `-WhatIf`；注销默认要求确认，且不会强制杀进程。

```powershell
.\scripts\unregister-package.ps1 -PackageRoot 'D:\实际的新副本目录' -WhatIf
.\scripts\unregister-package.ps1 -PackageRoot 'D:\实际的新副本目录'
```

注册恢复不是完整磁盘、应用资料库或云端状态回滚。重要资料需用户自行备份。脚本不自动删除新旧程序目录、快捷方式或应用数据。

本次打包未执行实际注册/注销，也未触碰当前可用安装。此前保留的 `.LTSC` 注册不由本项目删除，不建议把它作为主启动入口。