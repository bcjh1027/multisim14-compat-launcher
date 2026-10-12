# 更新记录

## 0.1.0（未发布）

首个版本。

- 双击入口 `Multisim兼容启动.cmd`：直接调用 `LEProc.exe -runas`，不经过 PowerShell，不受执行策略影响；路径含中文、空格、`&`、`()` 均已验证。
- 启动前校验：NI 三个文件的 SHA-256 白名单、LE 五个文件和配置的 SHA-256、Multisim 未在运行、目标旁无 `.le.config`。
- `install.ps1`：`irm | iex` 可用；不依赖 `$PSScriptRoot`；默认装到 `%LOCALAPPDATA%\MultisimCompat`，不需要管理员；从 NI 注册表（64 位视图）查找安装路径；HTTPS 下载、SHA-256 内置校验、3 次重试、镜像前缀；安装/更新/卸载/收集日志/检查；更新带回滚。
- `卸载.cmd`：只删桌面快捷方式和安装目录；拒绝在非安装目录、磁盘根目录、NI 目录里删除。
- 已验证构建：Multisim 14.0.593.0。
