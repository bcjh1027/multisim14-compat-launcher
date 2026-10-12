# 发布清单（GitHub Release）

仓库：<https://github.com/bcjh1027/multisim14-compat-launcher>

## 放哪里

| 内容 | 位置 | 理由 |
| --- | --- | --- |
| 脚本、配置、文档、许可证文本、测试 | **Git** | 自有内容（MIT）和许可证文本，可审阅、可 diff |
| `config/cmd-gate.txt`、`config/support-manifest.json` | Git | 哈希白名单必须随代码审阅 |
| `src/cmd/*.utf8`（cmd 源文件） | Git | UTF-8 便于看 diff；发布时转成 GBK + CRLF |
| `docs/evidence/*.png` | Git | 验证截图（小文件） |
| Locale Emulator 5 个运行时文件 | **只在 Release zip 里** | 第三方二进制，不进 Git 历史 |
| Locale Emulator 两份对应源码 zip | **只在 Release 附件里** | LGPL 要求随二进制提供源码；Core 那份 28 MB，不进 Git |
| `runtime/`、`vendor/`、`dist/`、`build/`、`logs/` | 不提交（`.gitignore`） | 本机产物 |
| NI 的任何文件 | 任何地方都没有 | 不分发 |

`tests/Run-Tests.ps1` 会检查：Git 跟踪文件和历史里没有 `.exe/.dll/.zip/.prd/.prj/.usr/.pfx/.key` 等。

## Release 附件（共 5 个）

由 `tools\Build-Release.ps1` 生成到 `dist\`：

| 文件 | 说明 |
| --- | --- |
| `install.ps1` | 已写入版本号和 zip 的 SHA-256 |
| `MultisimCompat-<版本>.zip` | 安装包：脚本、白名单、LE 的 5 个文件 + 配置 + 许可证 |
| `Locale-Emulator-2.5.0.1-source.zip` | LGPL 对应源码（`LEProc.exe`、`LECommonLibrary.dll`） |
| `Locale-Emulator-Core-ae7160d-source.zip` | LGPL 对应源码（`LoaderDll.dll`、`LocaleEmulator.dll`） |
| `SHA256SUMS.txt` | 以上文件的哈希 |

两份源码 zip 与安装包在**同一个 Release** 里，满足"随二进制提供对应源码"。不要只放链接。

## 发布步骤

1. 改 `VERSION`；如有新的已验证构建，改 `config/support-manifest.json`，然后：
   ```powershell
   .\tools\Build-Release.ps1 -RegenerateGate      # 重新生成 config\cmd-gate.txt
   ```
2. 跑测试，必须 0 失败：
   ```powershell
   .\tests\Run-Tests.ps1
   ```
3. 构建：
   ```powershell
   .\tools\Build-Release.ps1
   ```
4. 在**干净的** Windows 账户或虚拟机里，用 `dist\install.ps1` 加 `-ZipPath` 走一遍安装 → 检查 → 启动 → 卸载。（本机测试不能替代这一步。）
5. 提交、打标签、上传。标签必须是 `v<VERSION>`（`install.ps1` 按这个拼下载地址）：
   ```powershell
   git tag v0.1.0
   git push origin main v0.1.0
   gh release create v0.1.0 dist\* --title "v0.1.0" --notes-file <按下面的模板写好的说明文件>   # 先加 --draft 看一眼更稳
   ```
6. 发布后，**从 GitHub 上**重新下载 `install.ps1` 和 zip，核对哈希与 `SHA256SUMS.txt` 一致，再用 README 里的一行命令在测试环境装一次。

构建是可复现的：同一份源码连续构建两次，zip 哈希相同（固定时间戳、固定排序、不含机器信息）。

## LGPL-3.0 合规检查表

- [x] 许可证全文随安装包提供：`third_party/locale-emulator/LICENSE-LGPL-3.0.txt`、`LICENSE-GPL-3.0.txt`，以及运行时目录里的副本。
- [x] 版权与许可证声明保留：`THIRD_PARTY_NOTICES.md`、`LICENSE_SCOPE.md`。
- [x] 对应源码随 Release 提供，并注明哈希和上游地址。
- [x] 修改说明：未修改 LE 的二进制和源码；只挑选了 5 个文件、增加了自己的配置文件（`LEConfig.xml`，MIT）。
- [x] 允许用户替换：LE 以独立文件存在（动态链接，非静态嵌入），`MSCOMPAT_ALLOW_CUSTOM_RUNTIME=1` 可使用自己编译的版本。
- [x] 我们的 MIT 代码和 LGPL 部件分开标注，不把第三方文件重新许可。
- [ ] **待确认：** Core 源码对应的提交 `ae7160d` 是依据 PE 编译时间戳推定的，未用上游工具链重编译比对。发布说明里已如实写明；如果需要更严格证明，请联系上游。
- [ ] **待确认：** LE 的 `Loader`、`LoaderDll` 和 `LocaleEmulator` 有 `_Compilers`/`_WDK` 里的第三方工具链压缩包，已包含在 Core 源码 zip 中，我们没有逐个审查其许可证；分发的是上游原样 zip，没有改动。
- 本检查表是工程记录，不是法律意见。

## 商标与措辞

- 仓库名、Release 名称里不要把 Multisim / NI 写成项目来源或"官方"。
- README 保留：非官方声明、需自备合法授权、NI 商标归属。
- 不使用 NI 的标志。快捷方式图标引用本机 `multisim.exe` 自带的图标，不随包分发。

## 发布说明模板

```markdown
## 安装

irm https://github.com/bcjh1027/multisim14-compat-launcher/releases/latest/download/install.ps1 | iex

## 已验证
- Multisim 14.0.593.0 / Windows 11 25H2 (26200.9457) / 简体中文

## 未验证
- 其他 14.x 小版本、其他 Windows 版本、中文路径工程、用户元件库保存

## 许可证
自有代码 MIT；Locale Emulator 2.5.0.1 为 LGPL-3.0-only，对应源码在本 Release 附件中。

## 校验
见 SHA256SUMS.txt
```
