# 测试记录

## 1. 手动验证（2026-10-11，维护者本机）

| 项目 | 内容 |
| --- | --- |
| 系统 | Windows 11 25H2，build 26200.9457，简体中文原生安装（InstallLanguage 0804，系统区域 zh-CN，ACP 936） |
| Multisim | 14.0.593.0（产品版本 14.0.0.0，x86），NI 签名有效 |
| 兼容层 | Locale Emulator 2.5.0.1，en-US 配置，时区 China Standard Time，开启注册表重定向 |
| 启动命令 | `LEProc.exe -runas ffb361ae-febe-4cdb-aff4-0294d2623d1a "C:\Program Files (x86)\National Instruments\Circuit Design Suite 14.0\multisim.exe"` |

三个被锁定的 NI 文件（见 `config/support-manifest.json`）：

| 文件 | 文件版本 | SHA-256 |
| --- | --- | --- |
| `multisim.exe` | 14.0.593.0 | `2DAB05A8C2F97A872BA0A999C5F86544CF3E94CAD819551E580E287F8540D1DE` |
| `LibraryAccess.dll` | 14.0.0.0 | `6E952305A2D38831D246C76B93199817975979FDF4ECA34FB0866E20422F4DDB` |
| `WidgetLibrary.dll` | 14.0.0.0 | `7AC3E67BA8F13E5587E18F170520F014E228CD85BA96FC79CC7FAFAF491EE27E` |

结果（来自维护者的手动测试）：

| 项目 | 结果 |
| --- | --- |
| 数据库错误弹窗 | 消失 |
| Ctrl+W 元件库 | 恢复 |
| 直流工作点分析：12V 电源 + 3×1kΩ 串联 | V(2)=8.00000，V(3)=4.00000，与手算一致（[截图](evidence/dc-op-3x1k-12V.png)） |
| 连续手动启动 | 10 次，零故障 |

本机三个数据库（`MSComp_S.prd`、`CPComp_S.prj`、`UsrCompTemplate_S.usr`）文件头偏移 0x14 的 Jet 标记均为 0（旧式 Jet 3 格式），与已知故障画像一致。

**这一轮没有重新做的事**：上表是封装之前的手动验证。封装后的启动器（`.cmd`）只做了下面第 2 节的自动化演练，**没有**重新逐项走一遍元件库、分析和保存。

## 2. 封装后的自动化演练（`tests/Run-Tests.ps1`，56 项，0 失败）

在 Windows PowerShell 5.1、本机真实 Multisim 14.0.593 上运行。全程只写临时目录，不碰桌面和 NI 目录，不启动 Multisim。

覆盖的内容：

- 所有 `.ps1`/`.psm1` 语法；含中文的脚本带 BOM；`install.ps1` 不带 BOM 且中文只出现在 `T '...'` 里；cmd 源文件的字符都能用 GBK 表示。
- `cmd-gate.txt` 与 `support-manifest.json`、`LEConfig.xml` 逐项一致。
- 构建判定：精确三文件哈希为 Verified；主程序或数据库组件哈希变了为 Candidate；14.3.3 官方修复和 14.x 之外被拒绝。
- 运行时 5 个文件 + 配置的哈希、x86、GUID；不含更新器/安装器/GUI。
- Git 跟踪文件和历史不含二进制、归档、NI 数据库、证书；`runtime/`、`vendor/`、`dist/` 被排除；代码中没有密码恢复/解密逻辑。
- 发布构建，且同一份源码连续构建两次 zip 逐字节相同；安装包不含 NI 二进制；含 LGPL 文本和第三方声明；Release 附件里有 LE 两份源码。
- 安装到含中文、空格、`&`、`()` 的目录。
- `cmd /check` 在本机真实 Multisim 上全部通过；运行时文件被改一个字节 → 拒绝；`MSCOMPAT_ALLOW_CUSTOM_RUNTIME=1` → 只警告；目标旁有 `.le.config`（在临时副本上）→ 拒绝；三文件哈希不在白名单 → 拒绝。
- `卸载.cmd`：在非安装目录里拒绝删除任何东西；在安装目录里删除目录（含自身），不波及同级文件。

另外手工做过（不在自动化里）：`install.ps1` 在 `-ExecutionPolicy Restricted` 下通过 `irm | iex` 和 `[scriptblock]::Create(irm …)` 两种方式运行；HTTP 镜像被拒绝；zip 被追加一个字节后被 SHA-256 校验拒绝且未创建目标目录；安装 → 更新 → 收集反馈 → 卸载完整走通，桌面快捷方式随之创建和删除；反馈包里未发现用户名或邮箱。

## 3. 一次计划外的真实启动（数据点，不算正式测试）

调试 `/check` 参数时，较早版本的 `Multisim兼容启动.cmd` 没有识别 `/check`，在含中文、空格、`&`、`()` 的临时目录里真正启动了一次 Multisim：

- LEProc 注入成功，出现主窗口 `Design1 - Multisim - [Design1]`；
- 随后用 `WM_CLOSE` 正常关闭，约 6 秒内 `multisim.exe` 和 `LEProc.exe` 均已退出，无残留进程。

这说明从中文/特殊字符路径启动是可行的，但它不是按测试计划做的，没有检查数据库、分析或保存。

## 4. 尚未验证（请反馈）

- 其他 14.x 小版本（含 14.1、14.2、14.3.0–14.3.2）。
- 其他 Windows 版本：24H2 全新安装、Windows 10、非 Home 版本。
- 中文路径下打开/保存 `.ms14` 工程；中文元件名；用户元件库的创建、保存、重新打开。
- 与安全软件（Defender 之外的杀毒、EDR）共存。
- 带第三方插件的 Multisim。
- 安装目录在含中文用户名的账户下（Locale Emulator 本身从中文目录注入已验证；整条安装链未在中文用户名账户上跑过）。

## 5. 同学反馈模板

在仓库提 Issue 时使用 `.github/ISSUE_TEMPLATE/test-report.md`，或直接复制下面内容。收集资料的命令：

```powershell
irm https://github.com/bcjh1027/multisim14-compat-launcher/releases/latest/download/install.ps1 -OutFile "$env:TEMP\i.ps1"
& ([scriptblock]::Create([IO.File]::ReadAllText("$env:TEMP\i.ps1", [Text.Encoding]::UTF8))) -Action Logs
```

```text
【环境】
Windows 版本和 build（设置 → 系统 → 关于）：
系统语言：
Multisim 版本（Help → About）：
安装目录：
杀毒/安全软件：

【安装】
安装方式（一行命令 / 下载后检查 / 手动）：
是否使用镜像：
安装是否成功：是 / 否   报错原文：

【启动】
双击快捷方式后：成功进入主界面 / 没反应 / 报错
启动器提示的原文：
原生启动（不用本工具）时是否出现三个数据库错误：是 / 否 / 没试

【使用】（没做的写"没做"，不要猜）
Ctrl+W 元件库能打开：
放置元件并连线：
仿真/分析能得到结果：
保存工程后重新打开：
打开中文路径下的工程：
用户元件库：

【附件】
Multisim兼容检查.cmd 生成的 logs\check-latest.txt：
-Action Logs 生成的反馈文件夹（发送前请自己看一遍）：
```

## 6. 判定为"已验证"的标准

一个新构建要进入 `VerifiedBuilds`，除了没有弹窗，还必须：保存三个 NI 文件的版本和哈希；在原生环境确认出现三类数据库错误；兼容模式冷启动、正常退出、再次冷启动；分别浏览主库、企业库和用户库；在临时用户元件上完成创建、保存、重开和删除；检查事件日志、残留 `.ldb` 和进程；测试前后三个 NI 文件和三个数据库的哈希一致。

以下情况**不能**升级为已验证：只验证了"没有弹窗"；需要改系统区域、注册表、安装 DLL 或数据库才能工作；NI 签名无效；必须永久关闭安全软件；构建已包含 NI 官方的 14.3.3 修复。
