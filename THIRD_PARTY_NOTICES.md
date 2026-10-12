# 第三方组件声明

## Locale Emulator 2.5.0.1

- 作者：xupefei 及贡献者
- 许可证：**LGPL-3.0-only**（许可证全文：`third_party\locale-emulator\LICENSE-LGPL-3.0.txt`，它引用的 GPL-3.0 全文也在同目录）
- 项目主页：<https://github.com/xupefei/Locale-Emulator>
- 官方发布包：<https://github.com/xupefei/Locale-Emulator/releases/download/v2.5.0.1/Locale.Emulator.2.5.0.1.zip>
  - SHA-256：`808FF584426D52CC775AD6406DA00622F454BE95BD4C8FBCA42EEF4B7235AD5C`

### 本项目分发了哪些文件

安装包 `runtime\locale-emulator\` 里只有下面 5 个文件加两份许可证文本和一份配置。逐文件的 SHA-256 记录在 `config\support-manifest.json`，启动时每次都会校验。

| 文件 | 来源 | SHA-256 |
| --- | --- | --- |
| `LEProc.exe` | 官方发布包，原样 | `2A81CB20B5B705D84416FD8B1CD9A819B1CAFAECCC0C1E23C289884310EC0461` |
| `LoaderDll.dll` | 官方发布包，原样 | `82FAE0F44F4CA0C9C37907DF74CEF2415EEB5FAE1CF8D4F36F34FFCAF7E3CC0C` |
| `LocaleEmulator.dll` | 官方发布包，原样 | `C79C175FDAD174AA46A72197D148316299A56F950AAAB1B84930D09EE1084A88` |
| `LEVersion.xml` | 官方发布包，原样 | `F9C090E0A586F2F5FC83DB529E505C84570E399A850B7DE79D86896D90F6C811` |
| `LECommonLibrary.dll` | 从官方发布包内 `LEInstaller.exe` 的内嵌资源提取，字节原样（强名称公钥标记 `a5ce8326c28d7c91`，与 `LEProc.exe` 的引用一致） | `6EDBB48B891E3EE830E7B487F352D90044474A757905FF49D3B2ABFDB980C211` |

未分发：`LEUpdater.exe`、`LEInstaller.exe`、`LEGUI.exe`、资源管理器右键扩展、语言包。

### 修改说明

**本项目没有修改 Locale Emulator 的任何二进制或源码。** 我们只是：

1. 挑选其中 5 个运行时文件（省略了更新器、安装器、图形界面）；
2. 增加一份 `LEConfig.xml`：单一 en-US 配置，时区 China Standard Time，开启注册表重定向，不请求管理员权限（该文件是本项目自己的配置，MIT）。

仅此而已。因为省略了 `LEUpdater.exe`，`LEProc.exe` 启动时尝试调用更新器会静默失败（源码里是 `try { ... } catch { }`），这是预期行为，不会联网更新。

### 对应源码（LGPL 要求）

与本项目同一个 Release 里**一并上传**了下面两份源码包，你不需要联网到别处找：

| 文件 | 内容 | SHA-256 |
| --- | --- | --- |
| `Locale-Emulator-2.5.0.1-source.zip` | `LEProc.exe`、`LECommonLibrary.dll` 的源码（标签 `v2.5.0.1`） | `411529EF52F4E5EFC03E3A5B6750B3B372A2AC9917383CC39C8181B47B075ACF` |
| `Locale-Emulator-Core-ae7160d-source.zip` | `LoaderDll.dll`、`LocaleEmulator.dll` 的源码 | `80040EAB31970EC1381BFA57A2C00B507501487EFAC0220DBD3CD8FB37007941` |

上游地址：

- <https://github.com/xupefei/Locale-Emulator/archive/refs/tags/v2.5.0.1.zip>
- <https://github.com/xupefei/Locale-Emulator-Core/archive/ae7160dc5deb97947396abcd784f9b98b6ee38b3.zip>

**关于 Core 源码的版本：** Locale-Emulator-Core 没有打标签。我们把 `ae7160dc`（2021-08-23 18:43 UTC 的合并提交）选为对应源码，依据是官方发布包里 `LoaderDll.dll`、`LocaleEmulator.dll` 的 PE 编译时间戳分别是 2021-08-23 18:54 和 18:52 UTC，紧随该提交，并且该提交之后 Core 仓库再无提交。这是依据时间做的推定，我们**没有**用上游的专用工具链重新编译并比对二进制，所以不能声称“可逐字节复现”。如果你需要更严格的证明，请向上游确认。

### 你可以修改和替换它

LGPL 允许你修改 Locale Emulator 并替换发布包里的文件。因为启动器会校验这 5 个文件的哈希，换成自己编译的版本时请先设置环境变量再启动：

```bat
set MSCOMPAT_ALLOW_CUSTOM_RUNTIME=1
```

此时哈希不符只会警告，不会拒绝启动。（这条逃生口只放宽运行时文件的哈希检查，NI 三个文件的白名单检查不受影响。）

## JesseLee-CN/legacy-cds-db-compat-launcher

- 许可证：MIT，版权 © 2026 multisimcompatfix contributors
- 来源：<https://github.com/JesseLee-CN/legacy-cds-db-compat-launcher>，参考提交 `96530f2a0b10ffe4d6f769f51ec0e2844257ac85`
- 使用方式：`src\MultisimCompat.psm1`、`src\WindowsPowerShellBootstrap.ps1`、`multisim-compat.ps1` 以该项目为基础改写；`config\locale-emulator\LEConfig.xml` 取自该项目。MIT 版权声明保留在 `LICENSE`。

## 商标

Multisim™ 是 National Instruments 的商标。本项目是独立项目，与 NI 没有关联，未获得 NI 的认可、赞助或批准；不分发任何 NI 标志或 NI 软件。
