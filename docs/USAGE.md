# 使用说明

## 日常使用

双击桌面的 **Multisim 14.0 (兼容启动)**。窗口出现英文界面的 Multisim 就是成功的。

如果快捷方式被删了，直接双击安装目录里的 `Multisim兼容启动.cmd`。默认安装目录是 `%LOCALAPPDATA%\MultisimCompat`（在资源管理器地址栏粘贴这个路径即可打开）。

注意：
- 启动前要先关掉所有 Multisim。已经在运行的 Multisim 不会获得兼容环境，启动器会提示并退出。
- 想在 Multisim 里打开 `.ms14` 文件，先用兼容方式启动，再用"文件 → 打开"。直接双击 `.ms14` 会走系统默认方式，数据库错误会回来。

## 检查与排错

双击 `Multisim兼容检查.cmd`。它只读，不启动 Multisim，会把系统版本、三个 NI 文件的哈希和每一项检查的结果写到 `logs\check-latest.txt`。

| 启动器提示 | 意思 | 怎么办 |
| --- | --- | --- |
| 没有找到 Multisim 14.0 的安装路径 | 注册表里没有 14.0 | 确认装的是 14.0；或把 `multisim.exe` 完整路径写进安装目录 `config\multisim-path.txt` |
| 这个 Multisim 构建不在已验证列表里 | 三个文件哈希不匹配 | 把提示里的三行哈希和 `logs\launch.log` 反馈给维护者，**不要**自己改清单硬启动 |
| 兼容运行时文件缺失或被改动 | 杀毒软件删了文件，或文件损坏 | 重新运行安装脚本；并把安装目录加入杀毒软件白名单 |
| Multisim 已经在运行 | 同上 | 关闭所有 Multisim 后再启动 |
| multisim.exe 旁存在 .le.config | 有别的工具给 Multisim 配了 LE 配置，会覆盖本工具的 | 确认来源后自行处理，本工具不会替你删 |
| 20 秒内没有看到 multisim.exe 进程 | 点了没反应 | 很可能被安全软件拦截；见下 |

**点了没反应：** 临时关闭安全软件的实时防护再试一次，能启动就说明被拦截了，把安装目录加白名单。不建议永久关闭安全软件。

## 更新

重新运行安装命令即可。已是最新版本会提示并退出；有新版本会覆盖安装，保留 `logs\` 和你的 `config\multisim-path.txt`。

```powershell
# 强制重装当前版本
& ([scriptblock]::Create([IO.File]::ReadAllText("$env:TEMP\i.ps1", [Text.Encoding]::UTF8))) -Action Install -Force
```

## 安装脚本的参数

用 `& ([scriptblock]::Create(...)) -参数` 的形式传参。用 `irm | iex` 一行命令时，不能传参，改用环境变量。

| 参数 | 环境变量 | 说明 |
| --- | --- | --- |
| `-Action Install/Update/Uninstall/Logs/Check` | `MSCOMPAT_ACTION` | 默认 Install |
| `-InstallDir <目录>` | `MSCOMPAT_INSTALLDIR` | 默认 `%LOCALAPPDATA%\MultisimCompat`。不能是磁盘根目录、NI 目录、Windows 目录，也不能是已有的非本工具目录 |
| `-MirrorPrefix <https://…>` | `MSCOMPAT_MIRROR` | 前缀式镜像，只允许 HTTPS |
| `-BaseUrl <https://…>` | | 自己托管 zip 的目录 |
| `-ZipPath <文件>` | | 用本地已下载的安装包（离线安装），仍会校验内置 SHA-256 |
| `-MultisimPath <文件>` | | 手动指定 `multisim.exe` |
| `-NoShortcut` | | 不建桌面快捷方式 |
| `-Force` | | 同版本也重装 |
| `-Yes` | | 卸载时不询问 |
| `-PurgeLogs` | | 卸载时顺便删 `%LOCALAPPDATA%\MultisimCompatLogs` |

## 卸载

- 双击安装目录里的 `卸载.cmd`；或
- 运行安装脚本 `-Action Uninstall`。

两种方式都只删除桌面快捷方式和安装目录。它们会先确认这个目录确实是本工具的安装目录（有 `config\install.txt`、`config\cmd-gate.txt` 和 `runtime\locale-emulator\LEProc.exe`），并拒绝删除磁盘根目录和任何含 `National Instruments` 的路径。

## 收集反馈资料

```powershell
& ([scriptblock]::Create([IO.File]::ReadAllText("$env:TEMP\i.ps1", [Text.Encoding]::UTF8))) -Action Logs
```

会在桌面生成 `MultisimCompat-feedback-<时间>` 文件夹，里面有：系统版本、三个 NI 文件的哈希、安装日志和启动日志。路径里的用户名会被替换。**不含**你的工程文件、注册表导出或许可证信息。发出去之前建议自己打开看一遍。

## 进阶：命令行入口

`multisim-compat.ps1` 提供只读检查和候选构建的显式启动，面向愿意自己承担风险的用户：

```powershell
.\multisim-compat.ps1 -Action List        # 列出发现的 Multisim 14.x
.\multisim-compat.ps1                      # 只读检查，不启动
.\multisim-compat.ps1 -Action Start -AllowCandidateBuild -ConfirmDatabaseError
```

候选构建（14.0–14.3.2 里还没验证的小版本）需要同时给出两个开关，表示"我知道这个构建没验证过"和"我亲眼见过三个数据库错误"。它同样要求系统符合已知故障画像。双击入口 `.cmd` 不接受候选构建。

## 用自己编译的 Locale Emulator

LGPL 允许替换。把 `runtime\locale-emulator\` 里的文件换成自己编译的之后，设置环境变量再启动，哈希不符将只警告：

```bat
set MSCOMPAT_ALLOW_CUSTOM_RUNTIME=1
Multisim兼容启动.cmd
```

这只放宽运行时文件的哈希检查，NI 三个文件的白名单检查不受影响。
