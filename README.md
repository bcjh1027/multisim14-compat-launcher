# Multisim 14.0 兼容启动器（非官方）

在 Windows 11 24H2 及以上的**中文系统**上，Multisim 14.0 启动时弹出"主数据库 / 企业数据库 / 用户数据库无法访问"，元件库打不开。这个小工具只做一件事：**用 Locale Emulator 给 Multisim 一个 en-US 区域环境来启动它**，问题就不再出现。

- 只影响被启动的那个 Multisim 进程。不改系统区域、系统 DLL、NI 安装目录、NI 注册表项、Multisim 数据库、许可证和安全策略。
- 不含任何 NI 二进制，也不处理授权。**你需要自己安装并合法授权 Multisim 14.0。**
- 代价：被启动的 Multisim 界面显示英文。

> 本项目与 National Instruments 无关，未获 NI 认可。Multisim 是 NI 的商标。

## 先搞清楚你是不是这个问题

同时满足才需要它：

1. Windows 11 版本 24H2 或更高（版本号 ≥ 26100），系统语言是简体中文；
2. Multisim 14.0 一启动就连续弹出三个数据库错误，或者 Ctrl+W 打不开元件库。

NI 官方已在 14.3.3 修复这个问题。如果你用的是 14.3，优先装官方补丁，不要用本工具。

## 安装

### 方式一：一行命令（推荐）

打开**普通** PowerShell（不需要管理员），粘贴运行：

```powershell
irm https://github.com/bcjh1027/multisim14-compat-launcher/releases/latest/download/install.ps1 | iex
```

它会：找到你电脑上的 Multisim 14.0 → 下载安装包并校验 SHA-256 → 装到 `%LOCALAPPDATA%\MultisimCompat` → 在桌面生成快捷方式。

### 方式二：下载后检查再执行

不想直接执行网络上的脚本，就分两步：

```powershell
$u = 'https://github.com/bcjh1027/multisim14-compat-launcher/releases/latest/download/install.ps1'
irm $u -OutFile "$env:TEMP\mscompat-install.ps1"
notepad "$env:TEMP\mscompat-install.ps1"        # 看一遍
& ([scriptblock]::Create([IO.File]::ReadAllText("$env:TEMP\mscompat-install.ps1", [Text.Encoding]::UTF8)))
```

最后一行不是 `.\install.ps1`：这样不受执行策略（ExecutionPolicy）影响，也不会把脚本里的中文读成乱码。

### 方式三：完全手动（受限环境）

PowerShell 被策略限制（受限语言模式、WDAC）时用。到 [Releases](https://github.com/bcjh1027/multisim14-compat-launcher/releases) 下载 `MultisimCompat-<版本>.zip` 和 `SHA256SUMS.txt`，核对哈希后解压到任意目录，双击里面的 `Multisim兼容启动.cmd`。

```powershell
Get-FileHash .\MultisimCompat-0.1.0.zip -Algorithm SHA256     # 与 SHA256SUMS.txt 里的值比较
```

### 国内网络 / 镜像

GitHub 下载慢时，指定一个**支持 HTTPS** 的前缀式镜像（形如 `https://镜像域名/` + 原始 GitHub 地址）：

```powershell
$env:MSCOMPAT_MIRROR = 'https://你的镜像域名'
irm https://github.com/bcjh1027/multisim14-compat-launcher/releases/latest/download/install.ps1 | iex
```

镜像只负责转发 zip。安装包的 SHA-256 写在 `install.ps1` 里，镜像换内容会校验失败而拒绝安装。**但 `install.ps1` 本身必须从可信来源取**（上面的 GitHub 地址，或对照 `SHA256SUMS.txt`），不要也经由不可信镜像下载它。

## 使用

双击桌面的 **Multisim 14.0 (兼容启动)**，或安装目录里的 `Multisim兼容启动.cmd`。

每次启动前它会检查：

- 能找到 `multisim.exe`；
- `multisim.exe`、`LibraryAccess.dll`、`WidgetLibrary.dll` 三个文件的 SHA-256 在已验证列表里；
- Locale Emulator 的 5 个文件和配置的 SHA-256 完全一致；
- Multisim 当前没有在运行（已经在运行的进程不会获得兼容环境）；
- `multisim.exe` 旁边没有会覆盖配置的 `.le.config`。

任何一项不通过，都会说明原因并拒绝启动，不会尝试修复。

更多用法（更新、卸载、反馈、常见问题）见 [docs/USAGE.md](docs/USAGE.md)。

## 已验证的范围

目前**只验证了一个构建**：Multisim 14.0.593.0（x86，NI 签名有效），Windows 11 25H2（26200.9457），简体中文。在这台机器上：

- 数据库错误消失，Ctrl+W 元件库可用；
- 12V 电源 + 3 个 1kΩ 电阻串联，直流工作点分析得到 V(2)=8V、V(3)=4V，与手算一致（[截图](docs/evidence/dc-op-3x1k-12V.png)）；
- 连续 10 次手动启动无故障。

**没有验证**：中文路径的工程文件、用户元件库的保存、第三方插件、其他 14.x 小版本、其他 Windows 版本。细节与反馈方式见 [docs/TEST-RECORD.md](docs/TEST-RECORD.md)。你的构建如果不在已验证列表里，启动器会拒绝并打印三个哈希，欢迎反馈。

## 卸载

```powershell
irm https://github.com/bcjh1027/multisim14-compat-launcher/releases/latest/download/install.ps1 -OutFile "$env:TEMP\i.ps1"
& ([scriptblock]::Create([IO.File]::ReadAllText("$env:TEMP\i.ps1", [Text.Encoding]::UTF8))) -Action Uninstall
```

或者直接双击安装目录里的 `卸载.cmd`。只删除桌面快捷方式和安装目录，不碰 NI 的任何东西。

## 许可证

- 本项目自有代码和文档：MIT，见 [LICENSE](LICENSE)。
- 安装包里的 Locale Emulator 2.5.0.1：**LGPL-3.0-only**。对应源码随 Release 一并提供，替换方法见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)；各文件的许可证归属见 [LICENSE_SCOPE.md](LICENSE_SCOPE.md)。
- 门禁逻辑改写自 [JesseLee-CN/legacy-cds-db-compat-launcher](https://github.com/JesseLee-CN/legacy-cds-db-compat-launcher)（MIT）。

## 已知限制

- 被启动的 Multisim 是英文界面；中文路径、中文元件名的行为未逐项验证。
- 安全软件（EDR、杀毒）可能拦截 Locale Emulator 的进程注入，表现为点了没反应。
- 同一个问题也可能由数据库损坏、DAO 注册缺失等原因引起，这些情况兼容层帮不上忙。
