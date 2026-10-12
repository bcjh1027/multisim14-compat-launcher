# 许可证范围

## MIT：本项目自有内容

除下面列出的第三方文件外，本项目的 PowerShell 脚本、cmd 脚本、JSON/XML 配置、测试和文档按根目录 [LICENSE](LICENSE) 的 MIT License 授权。

部分脚本和 `multisim-compat.ps1`、`src\MultisimCompat.psm1` 的门禁逻辑改写自 [JesseLee-CN/legacy-cds-db-compat-launcher](https://github.com/JesseLee-CN/legacy-cds-db-compat-launcher)（MIT，参考提交 `96530f2`），其版权声明保留在 [LICENSE](LICENSE) 中。

## LGPL-3.0：Locale Emulator

发布包 `runtime\locale-emulator\` 目录里的下列文件来自 Locale Emulator 2.5.0.1，适用 **LGPL-3.0-only**，不是 MIT：

- `LEProc.exe`、`LECommonLibrary.dll`、`LEVersion.xml`（来自 [xupefei/Locale-Emulator](https://github.com/xupefei/Locale-Emulator)）
- `LoaderDll.dll`、`LocaleEmulator.dll`（来自 [xupefei/Locale-Emulator-Core](https://github.com/xupefei/Locale-Emulator-Core)）
- `LICENSE-GPL-3.0.txt`、`LICENSE-LGPL-3.0.txt`：许可证文本

`runtime\locale-emulator\LEConfig.xml` 是本项目写的一份配置文件（单一 en-US 配置），按 MIT 提供。

获取对应源码、修改和替换这些文件的方法见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 不在本项目范围内

- **NI / Multisim**：本项目不包含、不分发任何 NI 软件，也不处理授权。Multisim 是 National Instruments 的商标。
- 本项目与 NI 没有任何关联，也未获得 NI 认可或赞助。

## 商标

许可证不授予任何 NI、National Instruments、Multisim 或其他第三方商标权。这些名称只用于说明兼容对象。
