# 不再附带 Apple 完整清单

当前版本为减少第三方材料再分发风险，已删除曾从 Apple 包提取的 `AppxManifest.xml`。本项目未确认该文件的再分发授权；删除当前文件不等于清除 Git 历史或第三方副本。详见 [许可范围](../LICENSING.md) 和 [法律风险审查](../docs/legal-review.md)。

部署只能使用你有权取得和按适用许可处理的原始安装文件中的清单。本项目自编的 `tests/fixtures/AppxManifest.xml` 只是最小模拟夹具，不包含可部署应用声明，不能拿来替代 Apple 原清单或注册真实应用。
