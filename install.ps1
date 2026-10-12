# SPDX-License-Identifier: MIT
# Multisim 14.0 compat launcher - installer / updater / uninstaller / log collector (unofficial).
#
# Run (PowerShell, no admin needed):   irm <URL of this file> | iex
# Source layout: this file has NO BOM on purpose. Windows PowerShell 5.1 decodes `irm | iex` text as
# Latin-1 and a BOM breaks it, so Chinese strings go through T() which repairs the decoding at run time.
# Everything is wrapped in & { } so nothing leaks into the caller's session and parameters still work:
#   & ([scriptblock]::Create((Get-Content -Raw -Encoding UTF8 .\install.ps1))) -Action Uninstall
# Without parameters (irm | iex) use environment variables: MSCOMPAT_ACTION, MSCOMPAT_MIRROR, MSCOMPAT_INSTALLDIR.
#
# The release build (tools\Build-Release.ps1) stamps the @@...@@ values below, including the SHA-256 of the zip,
# so a mirror can never substitute a different payload.
& {
    [CmdletBinding()]
    param(
        [ValidateSet('Install', 'Update', 'Uninstall', 'Logs', 'Check')][string]$Action,
        [string]$InstallDir,
        [string]$MultisimPath,
        [string]$BaseUrl,
        [string]$MirrorPrefix,
        [string]$ZipPath,
        [string]$ExpectedSha256,
        [switch]$NoShortcut,
        [switch]$Force,
        [switch]$PurgeLogs,
        [switch]$Yes
    )

    $ErrorActionPreference = 'Stop'
    Set-StrictMode -Version Latest

    $Pinned = @{
        Version   = '@@VERSION@@'
        ZipName   = '@@ZIPNAME@@'
        ZipSha256 = '@@ZIPSHA256@@'
        Repo      = 'bcjh1027/multisim14-compat-launcher'
    }
    $Utf8 = [Text.Encoding]::UTF8
    $Latin1 = [Text.Encoding]::GetEncoding(28591)
    $Ansi = [Text.Encoding]::Default

    # ---- Chinese text handling (see header) --------------------------------------------------
    $probe = '中'
    if ($probe.Length -ne 1) {
        # Run as a .ps1 file without BOM: Windows PowerShell read it as ANSI. Re-read as UTF-8 and run again.
        $self = Get-Variable -Name PSCommandPath -ValueOnly -ErrorAction SilentlyContinue
        if ($self -and (Test-Path -LiteralPath $self -PathType Leaf)) {
            $text = [IO.File]::ReadAllText($self, $Utf8)
            & ([scriptblock]::Create($text)) @PSBoundParameters
            return
        }
    }
    $fixEnc = ($probe.Length -ne 1)
    function T([string]$s) {
        if ($fixEnc) { return $Utf8.GetString($Latin1.GetBytes($s)) }
        $s
    }
    if ($fixEnc -and ((T $probe).Length -ne 1)) {
        Write-Host 'Cannot decode the script text. Save it and run:'
        Write-Host '  & ([scriptblock]::Create((Get-Content -Raw -Encoding UTF8 .\install.ps1)))'
        return
    }

    if (-not $Action) { $Action = if ($env:MSCOMPAT_ACTION) { $env:MSCOMPAT_ACTION } else { 'Install' } }
    if ($Action -notin @('Install', 'Update', 'Uninstall', 'Logs', 'Check')) { throw "Invalid MSCOMPAT_ACTION: $Action" }
    if (-not $MirrorPrefix -and $env:MSCOMPAT_MIRROR) { $MirrorPrefix = $env:MSCOMPAT_MIRROR }
    if (-not $InstallDir -and $env:MSCOMPAT_INSTALLDIR) { $InstallDir = $env:MSCOMPAT_INSTALLDIR }

    # ---- logging -----------------------------------------------------------------------------
    $LogRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'MultisimCompatLogs'
    $LogFile = Join-Path $LogRoot 'install.log'
    function Write-Log([string]$m) {
        try {
            if (-not (Test-Path -LiteralPath $LogRoot)) { [void](New-Item -ItemType Directory -Path $LogRoot -Force) }
            Add-Content -LiteralPath $LogFile -Value ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8
        } catch { }
    }
    function Say([string]$m, [string]$kind = 'info') {
        $color = switch ($kind) { 'ok' { 'Green' } 'warn' { 'Yellow' } 'err' { 'Red' } 'step' { 'Cyan' } default { 'Gray' } }
        $prefix = switch ($kind) { 'ok' { '[OK] ' } 'warn' { '[!] ' } 'err' { '[X] ' } 'step' { '==> ' } default { '    ' } }
        Write-Host ($prefix + $m) -ForegroundColor $color
        Write-Log ($prefix + $m)
    }

    # ---- small helpers -----------------------------------------------------------------------
    function Get-Sha256([string]$Path) {
        $sha = [Security.Cryptography.SHA256]::Create()
        $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try { return ([BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '') }
        finally { $fs.Dispose(); $sha.Dispose() }
    }
    function Get-OemEncoding {
        # cmd.exe reads batch-side text files in the OEM code page; zh-CN is 936.
        $cp = 936
        try {
            $v = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -ErrorAction Stop).OEMCP
            if ($v) { $cp = [int]$v }
        } catch { }
        [Text.Encoding]::GetEncoding($cp)
    }
    function Hide-UserName([string]$s) {
        if (-not $s) { return $s }
        $s = $s.Replace($env:USERPROFILE, '%USERPROFILE%')
        $s -replace [regex]::Escape([Environment]::UserName), '<user>'
    }
    function Confirm-Action([string]$Prompt) {
        if ($Yes) { return $true }
        try { $a = Read-Host ($Prompt + ' [y/N]') }
        catch { throw (T '无法交互确认，请加 -Yes 参数重新运行。') }
        [regex]::IsMatch([string]$a, (T '^(y|yes|是)$'), 'IgnoreCase')
    }
    function Test-Running {
        @(Get-Process -Name 'multisim' -ErrorAction SilentlyContinue).Count -gt 0
    }
    $EntryName = T 'Multisim兼容启动.cmd'
    $ShortcutName = T 'Multisim 14.0 (兼容启动)'

    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        Say (T 'PowerShell 处于受限语言模式（可能是 WDAC / 安全策略），本安装脚本无法运行。') 'err'
        Say (T '请改用手动安装：见 README 的“手动安装”一节。') 'err'
        return
    }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

    # ---- locating things (all read-only) ----------------------------------------------------
    function Get-DefaultInstallDir { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'MultisimCompat' }
    function Find-Multisim14 {
        # HKLM\SOFTWARE\WOW6432Node\National Instruments\Circuit Design Suite\14.0\MSI Parts\Core\Path, read via the
        # 64-bit registry view so it works from both 32-bit and 64-bit PowerShell. No drive letters or user names assumed.
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
        try {
            $key = $base.OpenSubKey('SOFTWARE\WOW6432Node\National Instruments\Circuit Design Suite\14.0\MSI Parts\Core')
            if ($key) {
                try {
                    $p = [string]$key.GetValue('Path')
                    if ($p) {
                        $exe = Join-Path $p 'multisim.exe'
                        if (Test-Path -LiteralPath $exe -PathType Leaf) { return (Resolve-Path -LiteralPath $exe).Path }
                    }
                } finally { $key.Dispose() }
            }
        } finally { $base.Dispose() }
        $null
    }
    function Test-IsOurInstall([string]$Dir) {
        (Test-Path -LiteralPath (Join-Path $Dir 'config\install.txt') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Dir 'config\cmd-gate.txt') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Dir 'runtime\locale-emulator\LEProc.exe') -PathType Leaf)
    }
    function Assert-SafeInstallDir([string]$Dir) {
        $full = [IO.Path]::GetFullPath($Dir).TrimEnd('\')
        if ($full.Length -le 3) { throw (T '安装目录不能是磁盘根目录。') }
        if ($full -match 'National Instruments') { throw (T '安装目录不能放在 NI 的目录里。') }
        $win = [Environment]::GetFolderPath('Windows').TrimEnd('\')
        if ($full -eq $win -or $full.StartsWith($win + '\', 'OrdinalIgnoreCase')) { throw (T '安装目录不能放在 Windows 系统目录里。') }
        if ((Test-Path -LiteralPath $full) -and -not (Test-IsOurInstall $full)) {
            $any = @(Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($any.Count -gt 0) { throw ((T '目标目录已存在且不是本工具的安装目录，为避免误删，已拒绝：') + $full) }
        }
        $full
    }
    function Read-InstallInfo([string]$Dir) {
        $info = @{}
        $p = Join-Path $Dir 'config\install.txt'
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            foreach ($line in [IO.File]::ReadAllLines($p, (Get-OemEncoding))) {
                $i = $line.IndexOf('=')
                if ($i -gt 0) { $info[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim() }
            }
        }
        $info
    }

    # ---- download (HTTPS only, retry, SHA-256 pinned) ---------------------------------------
    function Get-ZipUrl {
        $leaf = '{0}/releases/download/v{1}/{2}' -f $Pinned.Repo, $Pinned.Version, $Pinned.ZipName
        if ($BaseUrl) { $url = ($BaseUrl.TrimEnd('/') + '/' + $Pinned.ZipName) }
        else { $url = 'https://github.com/' + $leaf }
        # MirrorPrefix is prepended to the full URL, e.g. https://mirror.example/ + https://github.com/...
        if ($MirrorPrefix) { $url = ($MirrorPrefix.TrimEnd('/') + '/' + $url) }
        if ($url -notmatch '^https://') { throw ((T '只允许 HTTPS 下载地址：') + $url) }
        $url
    }
    function Save-Download([string]$Url, [string]$Dest) {
        $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        try {
            $delays = @(0, 2, 5)
            for ($i = 0; $i -lt $delays.Count; $i++) {
                if ($delays[$i] -gt 0) { Start-Sleep -Seconds $delays[$i] }
                try {
                    Say (((T '下载（第 {0}/{1} 次）：') -f ($i + 1), $delays.Count) + $Url)
                    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -TimeoutSec 60
                    return
                } catch {
                    Say ((T '下载失败：') + $_.Exception.Message) 'warn'
                    if (Test-Path -LiteralPath $Dest) { Remove-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue }
                    if ($i -eq $delays.Count - 1) { throw }
                }
            }
        } finally { $ProgressPreference = $old }
    }
    function Get-VerifiedZip([string]$WorkDir) {
        $want = $ExpectedSha256
        if (-not $want -and $Pinned.ZipSha256 -notmatch '@@') { $want = $Pinned.ZipSha256 }
        if (-not $want) { throw (T '这是未打包的源码版 install.ps1，没有内置校验值。请从 Release 下载 install.ps1，或用 -ZipPath 配合 -ExpectedSha256。') }
        if ($ZipPath) { $zip = (Resolve-Path -LiteralPath $ZipPath).Path; Say ((T '使用本地安装包：') + $zip) }
        else { $zip = Join-Path $WorkDir $Pinned.ZipName; Save-Download (Get-ZipUrl) $zip }
        $got = Get-Sha256 $zip
        if ($got -ne $want.ToUpperInvariant()) {
            throw ((T '安装包 SHA-256 不符，已拒绝使用。期望 {0}，实际 {1}。') -f $want, $got)
        }
        Say (T '安装包 SHA-256 校验通过。') 'ok'
        $zip
    }
    function Expand-ZipSafely([string]$Zip, [string]$Dest) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $root = [IO.Path]::GetFullPath($Dest).TrimEnd('\') + '\'
        $arc = [IO.Compression.ZipFile]::OpenRead($Zip)
        try {
            foreach ($e in $arc.Entries) {
                if ($e.FullName.EndsWith('/') -or $e.FullName.EndsWith('\')) { continue }
                $target = [IO.Path]::GetFullPath((Join-Path $Dest ($e.FullName -replace '/', '\')))
                if (-not $target.StartsWith($root, 'OrdinalIgnoreCase')) { throw ((T '安装包含非法路径，已拒绝：') + $e.FullName) }
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
                [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
            }
        } finally { $arc.Dispose() }
    }

    # ---- actions ------------------------------------------------------------------------------
    function New-DesktopShortcut([string]$Entry, [string]$MultisimExe) {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $lnk = Join-Path $desktop ($ShortcutName + '.lnk')
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($lnk)
        $sc.TargetPath = $Entry
        $sc.WorkingDirectory = Split-Path -Parent $Entry
        if ($MultisimExe) { $sc.IconLocation = $MultisimExe + ',0' }
        $sc.Description = 'Unofficial Locale Emulator launcher for a locally licensed NI Multisim 14.0'
        $sc.Save()
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        $lnk
    }

    function Invoke-Install([bool]$IsUpdate) {
        if (Test-Running) { throw (T 'Multisim 正在运行，请先关闭它再安装或更新。') }
        $dir = Assert-SafeInstallDir $(if ($InstallDir) { $InstallDir } else { Get-DefaultInstallDir })
        $exists = Test-IsOurInstall $dir
        if ($IsUpdate -and -not $exists) { throw ((T '没有在这里找到已安装的版本，无法更新：') + $dir) }
        if ($exists -and -not $IsUpdate -and -not $Force) {
            $cur = (Read-InstallInfo $dir)['VERSION']
            Say ((T '已安装版本 {0}，目标版本 {1}。按“更新”覆盖，或加 -Force 重装。') -f $cur, $Pinned.Version) 'warn'
            if ($cur -eq $Pinned.Version) { Say (T '已是最新，无需操作。') 'ok'; return }
            $IsUpdate = $true
        }

        $ms = $MultisimPath
        if ($ms) {
            if (-not (Test-Path -LiteralPath $ms -PathType Leaf)) { throw ((T '指定的 multisim.exe 不存在：') + $ms) }
            $ms = (Resolve-Path -LiteralPath $ms).Path
        } else {
            $ms = Find-Multisim14
        }
        if ($ms) { Say ((T '找到 Multisim：') + $ms) 'ok' }
        else { Say (T '没有在注册表里找到 Multisim 14.0。仍会安装启动器；启动时如果找不到，会提示你指定路径。') 'warn' }

        $work = Join-Path ([IO.Path]::GetTempPath()) ('mscompat-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $work -Force)
        $stage = $dir + '.new'
        $backup = $dir + '.old'
        try {
            Say (T '准备安装包') 'step'
            $zip = Get-VerifiedZip $work
            if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
            Expand-ZipSafely $zip $stage

            # The zip has one top-level folder 'MultisimCompat'; flatten it.
            $inner = Join-Path $stage 'MultisimCompat'
            if (Test-Path -LiteralPath $inner -PathType Container) {
                $flat = $dir + '.flat'
                if (Test-Path -LiteralPath $flat) { Remove-Item -LiteralPath $flat -Recurse -Force }
                Move-Item -LiteralPath $inner -Destination $flat
                Remove-Item -LiteralPath $stage -Recurse -Force
                Move-Item -LiteralPath $flat -Destination $stage
            }
            foreach ($need in 'config\cmd-gate.txt', 'runtime\locale-emulator\LEProc.exe', $EntryName) {
                if (-not (Test-Path -LiteralPath (Join-Path $stage $need) -PathType Leaf)) { throw ((T '安装包内容不完整，缺少：') + $need) }
            }

            # Re-verify the runtime files against the gate list shipped in the same package.
            foreach ($line in [IO.File]::ReadAllLines((Join-Path $stage 'config\cmd-gate.txt'))) {
                $f = $line.Split(',')
                if ($f[0] -eq 'R' -and $f.Count -ge 3) {
                    $p = Join-Path $stage ('runtime\locale-emulator\' + $f[2])
                    if (-not (Test-Path -LiteralPath $p -PathType Leaf) -or (Get-Sha256 $p) -ne $f[1].ToUpperInvariant()) {
                        throw ((T '运行时文件校验失败：') + $f[2])
                    }
                }
            }

            # Keep per-user state across updates.
            if ($exists) {
                foreach ($keep in 'logs', 'config\multisim-path.txt') {
                    $src = Join-Path $dir $keep
                    if (Test-Path -LiteralPath $src) {
                        $dst = Join-Path $stage $keep
                        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force)
                        Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
                    }
                }
            }
            if ($ms) {
                [IO.File]::WriteAllText((Join-Path $stage 'config\multisim-path.txt'), $ms + "`r`n", (Get-OemEncoding))
            }

            # Swap in with rollback.
            Say (T '写入安装目录') 'step'
            if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
            if (Test-Path -LiteralPath $dir) { Move-Item -LiteralPath $dir -Destination $backup }
            try { Move-Item -LiteralPath $stage -Destination $dir }
            catch {
                if (Test-Path -LiteralPath $backup) { Move-Item -LiteralPath $backup -Destination $dir -ErrorAction SilentlyContinue }
                throw
            }

            $lnk = ''
            if (-not $NoShortcut) {
                try { $lnk = New-DesktopShortcut (Join-Path $dir $EntryName) $ms; Say ((T '已创建桌面快捷方式：') + $lnk) 'ok' }
                catch { Say ((T '创建快捷方式失败（不影响使用）：') + $_.Exception.Message) 'warn' }
            }
            # Keep the parentheses: the comma binds tighter than +, so without them two items merge into one line.
            $infoLines = @(('VERSION=' + $Pinned.Version), ('INSTALLED=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
            if ($lnk) { $infoLines += ('SHORTCUT=' + $lnk) }
            [IO.File]::WriteAllLines((Join-Path $dir 'config\install.txt'), $infoLines, (Get-OemEncoding))
            if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue }

            Say ((T '安装完成：') + $dir) 'ok'
            Say (T '之后双击桌面快捷方式，或安装目录里的“Multisim兼容启动.cmd”即可。') 'info'
            Say (T '先运行一次“Multisim兼容检查.cmd”可以确认你的构建在已验证列表里。') 'info'
        }
        finally {
            if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    function Invoke-Uninstall {
        $dir = [IO.Path]::GetFullPath($(if ($InstallDir) { $InstallDir } else { Get-DefaultInstallDir })).TrimEnd('\')
        if (-not (Test-IsOurInstall $dir)) { Say ((T '这里没有找到本工具的安装：') + $dir) 'warn'; return }
        if ($dir -match 'National Instruments') { throw (T '拒绝操作 NI 的目录。') }
        $info = Read-InstallInfo $dir
        Say (T '将删除：') 'step'
        Say ((T '安装目录：') + $dir)
        if ($info['SHORTCUT']) { Say ((T '桌面快捷方式：') + $info['SHORTCUT']) }
        Say (T '不会改动：Multisim 本体、NI 注册表、数据库、许可证、系统设置。')
        if (-not (Confirm-Action (T '确认卸载？'))) { Say (T '已取消。'); return }
        if ($info['SHORTCUT'] -and (Test-Path -LiteralPath $info['SHORTCUT'] -PathType Leaf) -and $info['SHORTCUT'] -like '*.lnk') {
            Remove-Item -LiteralPath $info['SHORTCUT'] -Force
            Say (T '已删除桌面快捷方式。') 'ok'
        }
        if ($PurgeLogs -and (Test-Path -LiteralPath $LogRoot)) {
            Remove-Item -LiteralPath $LogRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $dir -Recurse -Force
        Say (T '卸载完成。') 'ok'
    }

    function Invoke-Logs {
        $dir = [IO.Path]::GetFullPath($(if ($InstallDir) { $InstallDir } else { Get-DefaultInstallDir })).TrimEnd('\')
        $out = Join-Path ([Environment]::GetFolderPath('Desktop')) ('MultisimCompat-feedback-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        [void](New-Item -ItemType Directory -Path $out -Force)
        $sb = New-Object Text.StringBuilder
        [void]$sb.AppendLine('time: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
        [void]$sb.AppendLine('os: ' + [Environment]::OSVersion.VersionString)
        try { [void]$sb.AppendLine('ubr: ' + (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR) } catch { }
        try { [void]$sb.AppendLine('install-language: ' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language').InstallLanguage) } catch { }
        [void]$sb.AppendLine('culture: ' + [Globalization.CultureInfo]::CurrentCulture.Name)
        [void]$sb.AppendLine('ps: ' + $PSVersionTable.PSVersion + ' / ' + $ExecutionContext.SessionState.LanguageMode)
        [void]$sb.AppendLine('installed: ' + (Test-IsOurInstall $dir))
        if (Test-IsOurInstall $dir) { foreach ($k in (Read-InstallInfo $dir).GetEnumerator()) { [void]$sb.AppendLine('install.' + $k.Key + ': ' + (Hide-UserName $k.Value)) } }
        $pathFile = Join-Path $dir 'config\multisim-path.txt'
        $ms = $null
        if ((Test-IsOurInstall $dir) -and (Test-Path -LiteralPath $pathFile -PathType Leaf)) {
            $ms = [IO.File]::ReadAllLines($pathFile, (Get-OemEncoding)) | Select-Object -First 1
        }
        if (-not $ms) { $ms = Find-Multisim14 }
        if ($ms -and (Test-Path -LiteralPath $ms -PathType Leaf)) {
            $d = Split-Path -Parent $ms
            foreach ($f in 'multisim.exe', 'LibraryAccess.dll', 'WidgetLibrary.dll') {
                $p = Join-Path $d $f
                if (Test-Path -LiteralPath $p -PathType Leaf) {
                    [void]$sb.AppendLine(('{0}: {1} fv={2}' -f $f, (Get-Sha256 $p), (Get-Item -LiteralPath $p).VersionInfo.FileVersion))
                } else { [void]$sb.AppendLine($f + ': missing') }
            }
            [void]$sb.AppendLine('multisim-path: ' + (Hide-UserName $ms))
        } else { [void]$sb.AppendLine('multisim: not found') }
        [void]$sb.AppendLine('multisim-running: ' + (Test-Running))
        [IO.File]::WriteAllText((Join-Path $out 'summary.txt'), $sb.ToString(), $Utf8)
        foreach ($src in @((Join-Path $dir 'logs'), $LogRoot)) {
            if (Test-Path -LiteralPath $src) {
                foreach ($f in Get-ChildItem -LiteralPath $src -File -Filter *.log -ErrorAction SilentlyContinue) {
                    $txt = Hide-UserName ([IO.File]::ReadAllText($f.FullName, (Get-OemEncoding)))
                    [IO.File]::WriteAllText((Join-Path $out $f.Name), $txt, $Utf8)
                }
                $chk = Join-Path $src 'check-latest.txt'
                if (Test-Path -LiteralPath $chk) { [IO.File]::WriteAllText((Join-Path $out 'check-latest.txt'), (Hide-UserName ([IO.File]::ReadAllText($chk, (Get-OemEncoding)))), $Utf8) }
            }
        }
        Say ((T '反馈资料已收集到桌面文件夹：') + $out) 'ok'
        Say (T '里面只有系统版本、文件哈希和启动日志（用户名已替换），没有你的工程文件。请打包后发给维护者。') 'info'
    }

    function Invoke-Check {
        $dir = [IO.Path]::GetFullPath($(if ($InstallDir) { $InstallDir } else { Get-DefaultInstallDir })).TrimEnd('\')
        if (-not (Test-IsOurInstall $dir)) { throw ((T '尚未安装：') + $dir) }
        $cmd = Join-Path $dir (T 'Multisim兼容检查.cmd')
        Say ((T '运行检查：') + $cmd) 'step'
        & $env:ComSpec /c ('"' + $cmd + '"')
    }

    # ---- main ---------------------------------------------------------------------------------
    Write-Log ('=== start action={0} version={1} ps={2}' -f $Action, $Pinned.Version, $PSVersionTable.PSVersion)
    try {
        switch ($Action) {
            'Install'   { Invoke-Install $false }
            'Update'    { Invoke-Install $true }
            'Uninstall' { Invoke-Uninstall }
            'Logs'      { Invoke-Logs }
            'Check'     { Invoke-Check }
        }
    } catch {
        Say ($_.Exception.Message) 'err'
        Say ((T '详细日志：') + $LogFile) 'info'
        Write-Log ($_ | Out-String)
        $global:LASTEXITCODE = 1
    }
} @args
