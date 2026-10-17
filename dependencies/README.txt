如果当前用户缺少依赖，请从 Microsoft 官方渠道取得以下 x64 框架 APPX/MSIX 后放入本目录：
Microsoft.VCLibs.140.00.UWPDesktop >= 14.0.33728.0
Microsoft.VCLibs.140.00 >= 14.0.33519.0
依赖也必须声明支持 Windows Build 19044。
部署脚本只安装缺失的符合原始清单身份/Publisher/架构/版本的文件；签名由 Windows 部署服务验证。
不接受第三方 EXE、不导入证书，不联网自动下载。不把这些文件加入项目分享包。
只能使用你有权获取、使用并按适用许可处理的文件。官方来源或管理员权限不自动授权修改/再分发；先阅读根目录 DISCLAIMER.md 和 docs/legal-review.md。不把原包或修改目录上传本仓库。
