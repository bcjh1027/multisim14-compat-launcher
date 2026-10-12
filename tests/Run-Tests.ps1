# SPDX-License-Identifier: MIT
# 静态与烟雾测试。不会启动 Multisim，不写桌面，不碰 NI 目录；只在临时目录里做安装/卸载演练。
#   .\tests\Run-Tests.ps1                 全部（含本机集成：读取本机 Multisim 的哈希和注册表）
#   .\tests\Run-Tests.ps1 -SkipMachine    跳过本机集成（CI 用）
[CmdletBinding()]
param([switch]$SkipMachine)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $root 'src\MultisimCompat.psm1') -Force
$utf8 = [Text.UTF8Encoding]::new($false)
$script:Pass = 0
$script:Fail = 0
function Ok([bool]$Cond, [string]$Msg) {
    if ($Cond) { $script:Pass++; Write-Host "[通过] $Msg" }
    else { $script:Fail++; Write-Host "[失败] $Msg" -ForegroundColor Red }
}

# ---- 1. 语法 --------------------------------------------------------------------------------
foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File |
        Where-Object { $_.Extension -in '.ps1', '.psm1' -and $_.FullName -notmatch '\\(vendor|dist|runtime|build)\\' })) {
    $t = $null; $e = $null
    [void][Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($f.FullName, $utf8), [ref]$t, [ref]$e)
    Ok ($e.Count -eq 0) ("PowerShell 语法：" + $f.FullName.Substring($root.Length + 1))
}

# ---- 2. 编码约定 ------------------------------------------------------------------------------
foreach ($rel in 'src\MultisimCompat.psm1', 'src\WindowsPowerShellBootstrap.ps1', 'multisim-compat.ps1', 'tools\Build-Release.ps1', 'tests\Run-Tests.ps1') {
    $b = [IO.File]::ReadAllBytes((Join-Path $root $rel))
    $nonAscii = @($b | Where-Object { $_ -gt 0x7F } | Select-Object -First 1).Count -gt 0
    $bom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
    Ok (-not $nonAscii -or $bom) "含中文的 .ps1 必须带 UTF-8 BOM（Windows PowerShell 5.1 才能读对）：$rel"
}
$ib = [IO.File]::ReadAllBytes((Join-Path $root 'install.ps1'))
Ok (-not ($ib.Length -ge 3 -and $ib[0] -eq 0xEF -and $ib[1] -eq 0xBB -and $ib[2] -eq 0xBF)) 'install.ps1 不能带 BOM（irm | iex 会因此报错）'
$instText = [IO.File]::ReadAllText((Join-Path $root 'install.ps1'), $utf8)
$stray = 0
foreach ($line in $instText -split "`n") {
    if ($line -match '[^\x00-\x7f]') {
        $r = [regex]::Replace($line, "T '[^']*'", "T ''")
        if ($r -match '[^\x00-\x7f]' -and $line -notmatch "^\s*\`$probe = '.'\s*$") { $stray++ }
    }
}
Ok ($stray -eq 0) 'install.ps1 里的中文只出现在 T ''...'' 字面量中'
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $root 'src\cmd') -Filter *.utf8)) {
    $text = [IO.File]::ReadAllText($f.FullName, $utf8)
    $gbkOk = $true
    try { [void][Text.Encoding]::GetEncoding(936, [Text.EncoderExceptionFallback]::new(), [Text.DecoderExceptionFallback]::new()).GetBytes($text) } catch { $gbkOk = $false }
    Ok $gbkOk "cmd 源文件所有字符都能用 GBK 表示：$($f.Name)"
    $echoBad = @($text -split "`n" | Where-Object { $_ -match '^\s*echo\s' -and $_ -match '[<>|&^]' -and $_ -notmatch '"' })
    Ok ($echoBad.Count -eq 0) "cmd 的 echo 行没有裸露的重定向/转义字符：$($f.Name)"
}

# ---- 3. 清单一致性 ----------------------------------------------------------------------------
$manifest = Import-SupportManifest $root
Ok ($manifest.SchemaVersion -eq 2) '支持清单版本为 2'
Ok ($manifest.RuntimePackage.License -eq 'LGPL-3.0-only') '运行时许可证标识为 LGPL-3.0-only'
Ok (@($manifest.VerifiedBuilds | Where-Object { $_.MultisimSha256 -notmatch '^[A-F0-9]{64}$' -or $_.LibraryAccessSha256 -notmatch '^[A-F0-9]{64}$' -or $_.WidgetLibrarySha256 -notmatch '^[A-F0-9]{64}$' }).Count -eq 0) 'VerifiedBuilds 的哈希格式有效'
$gateRepo = ([IO.File]::ReadAllText((Join-Path $root 'config\cmd-gate.txt'), $utf8) -replace "`r`n", "`n").TrimEnd()
$expect = [Collections.Generic.List[string]]::new()
foreach ($b in @($manifest.VerifiedBuilds)) { $expect.Add(('B,{0},{1},{2},{3}' -f $b.MultisimSha256, $b.LibraryAccessSha256, $b.WidgetLibrarySha256, $b.Name)) }
foreach ($f in @($manifest.RuntimeFiles)) { $expect.Add(('R,{0},{1}' -f $f.Sha256, $f.Path)) }
$expect.Add(('R,{0},LEConfig.xml' -f (Get-FileSha256 (Join-Path $root 'config\locale-emulator\LEConfig.xml'))))
$gateData = @($gateRepo -split "`n" | Where-Object { $_ -match '^[BR],' })
Ok (($gateData -join "`n") -eq ($expect -join "`n")) 'config\cmd-gate.txt 与 support-manifest.json / LEConfig.xml 一致'

# ---- 4. 构建状态判定 --------------------------------------------------------------------------
$b0 = $manifest.VerifiedBuilds[0]
function Disp($pv, $fv, $m, $lv, $l, $w) {
    (Get-BuildDisposition -ProductVersion ([version]$pv) -FileVersion ([version]$fv) -MultisimSha256 $m -LibraryAccessVersion ([version]$lv) -LibraryAccessSha256 $l -WidgetLibrarySha256 $w -Manifest $manifest).State
}
Ok ((Disp '14.0.0.0' '14.0.593.0' $b0.MultisimSha256 '14.0.0.0' $b0.LibraryAccessSha256 $b0.WidgetLibrarySha256) -eq 'Verified') '14.0.593 精确三文件哈希 => Verified'
Ok ((Disp '14.0.0.0' '14.0.593.0' ('A' * 64) '14.0.0.0' $b0.LibraryAccessSha256 $b0.WidgetLibrarySha256) -eq 'Candidate') '主程序哈希不同 => Candidate（不会被当成已验证）'
Ok ((Disp '14.0.0.0' '14.0.593.0' $b0.MultisimSha256 '14.0.0.0' ('B' * 64) $b0.WidgetLibrarySha256) -eq 'Candidate') '数据库组件哈希不同 => Candidate'
Ok ((Disp '14.3.0.0' '14.3.1482.0' ('A' * 64) '14.3.1500.0' '1270453B8ED94FDBD4BB554493898BB036EA45DC989A99B5AC603AB270F7A68B' ('C' * 64)) -eq 'OfficialFixAvailable') '14.3.3 的 NI 官方修复 => 拒绝兼容层'
Ok ((Disp '15.0.0.0' '15.0.0.0' ('A' * 64) '15.0.0.0' ('B' * 64) ('C' * 64)) -eq 'Unsupported') '14.x 之外 => Unsupported'

# ---- 5. 运行时 --------------------------------------------------------------------------------
$rt = Get-RuntimeCompatibilityState -RepositoryRoot $root -Manifest $manifest -RuntimeRoot (Join-Path $root 'runtime\locale-emulator')
Ok $rt.Valid 'runtime\locale-emulator 哈希、x86、配置（含 GUID）全部有效'
Ok ($rt.ForbiddenFiles.Count -eq 0) '运行时不含 LEUpdater / LEInstaller / LEGUI'
$cfgRepo = Get-FileSha256 (Join-Path $root 'config\locale-emulator\LEConfig.xml')
Ok ($cfgRepo -eq (Get-FileSha256 (Join-Path $root 'runtime\locale-emulator\LEConfig.xml'))) 'runtime 里的 LEConfig.xml 与受控副本一致'

# ---- 6. 仓库策略 ------------------------------------------------------------------------------
if (Test-Path -LiteralPath (Join-Path $root '.git')) {
    $safe = $root.Replace('\', '/')
    $tracked = @(& git -c "safe.directory=$safe" -C $root ls-files)
    $bad = @('.exe', '.dll', '.zip', '.7z', '.cab', '.reg', '.lic', '.mdb', '.accdb', '.prd', '.prj', '.usr', '.ms14', '.pfx', '.key')
    $hits = @($tracked | Where-Object { [IO.Path]::GetExtension($_).ToLowerInvariant() -in $bad })
    Ok ($hits.Count -eq 0) ("Git 跟踪文件不含二进制/归档/NI 数据库/证书：" + ($hits -join ', '))
    $hist = @(& git -c "safe.directory=$safe" -C $root log --all --name-only --pretty=format: 2>$null | Where-Object { $_ } | Sort-Object -Unique |
            Where-Object { [IO.Path]::GetExtension($_).ToLowerInvariant() -in $bad })
    Ok ($hist.Count -eq 0) ("Git 历史也不含：" + ($hist -join ', '))
    foreach ($p in 'runtime/locale-emulator/LEProc.exe', 'vendor/x', 'dist/a.zip') {
        $ig = @(& git -c "safe.directory=$safe" -C $root check-ignore (Join-Path $root $p))
        Ok ($ig.Count -gt 0) ".gitignore 已排除：$p"
    }
} else { Write-Host '[跳过] 不在 Git 工作树中，跳过仓库策略检查。' }

# 禁止的敏感功能：不写“从数据库头恢复明文密码”之类代码
$scanned = @(Get-ChildItem -LiteralPath $root -Recurse -File |
        Where-Object { $_.Extension -in '.ps1', '.psm1', '.utf8' -and $_.FullName -notmatch '\\(vendor|dist|runtime|build|third_party)\\' -and $_.Name -ne 'Run-Tests.ps1' })
$sensitive = @($scanned | Select-String -Pattern 'password|passwd|口令|明文密码|RC4|decrypt' -SimpleMatch:$false -CaseSensitive:$false | Where-Object { $_.Line -notmatch '^\s*#|^\s*rem ' })
Ok ($sensitive.Count -eq 0) ("代码中没有密码恢复/解密相关逻辑：" + (($sensitive | Select-Object -First 3 | ForEach-Object { $_.Path + ':' + $_.LineNumber }) -join '; '))

# ---- 7. 打包 + cmd 烟雾测试（临时目录，中文/空格/与号/括号路径） --------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('mscompat-test-' + [guid]::NewGuid().ToString('N'))
try {
    [void](New-Item -ItemType Directory -Path $tmp -Force)
    $dist = Join-Path $tmp 'dist'
    & (Join-Path $root 'tools\Build-Release.ps1') -OutDir $dist | Out-Null
    $zip = Get-ChildItem -LiteralPath $dist -Filter 'MultisimCompat-*.zip' | Select-Object -First 1 -ExpandProperty FullName
    Ok ($null -ne $zip) '发布构建成功'
    $z1 = Get-FileSha256 $zip
    & (Join-Path $root 'tools\Build-Release.ps1') -OutDir (Join-Path $tmp 'dist2') | Out-Null
    Ok ($z1 -eq (Get-FileSha256 (Get-ChildItem -LiteralPath (Join-Path $tmp 'dist2') -Filter 'MultisimCompat-*.zip').FullName)) '同一份源码构建两次，zip 逐字节相同（可复现）'

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $arc = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $names = @($arc.Entries | ForEach-Object FullName)
        Ok (@($names | Where-Object { $_ -match '(?i)(multisim|LibraryAccess|WidgetLibrary)\.(exe|dll)$|LEUpdater|LEInstaller|LEGUI' }).Count -eq 0) '安装包不含 NI 二进制，也不含 LE 更新器/安装器/GUI'
        Ok (@($names | Where-Object { $_ -match 'Locale-Emulator.*source' }).Count -eq 0) 'LGPL 源码是 Release 的独立附件，不在安装包内（体积 28MB）'
        Ok ($names -contains 'MultisimCompat/third_party/locale-emulator/LICENSE-LGPL-3.0.txt') '安装包含 LGPL-3.0 许可证文本'
        Ok ($names -contains 'MultisimCompat/THIRD_PARTY_NOTICES.md') '安装包含第三方声明'
    } finally { $arc.Dispose() }
    Ok ((Get-ChildItem -LiteralPath $dist -Filter 'Locale-Emulator-*-source.zip').Count -eq 2) 'Release 附件含 LE 主仓库与 Core 两份对应源码'

    $inst = Join-Path $tmp '张三 test & (x86)\MultisimCompat'
    $sb = [scriptblock]::Create([IO.File]::ReadAllText((Join-Path $dist 'install.ps1'), $utf8))
    $out = & $sb -InstallDir $inst -ZipPath $zip -NoShortcut -Yes 6>&1 | Out-String
    Ok (Test-Path -LiteralPath (Join-Path $inst 'config\install.txt')) '安装到含中文/空格/与号/括号的目录成功'

    $wrap = Join-Path $tmp 'w.cmd'
    $gbk = [Text.Encoding]::GetEncoding(936)
    function Run-Cmd([string]$Script, [string]$CmdArgs, [hashtable]$Env = @{}) {
        $lines = @('@echo off')
        foreach ($k in $Env.Keys) { $lines += "set `"$k=$($Env[$k])`"" }
        $lines += "call `"$Script`" $CmdArgs"
        $lines += 'exit /b %errorlevel%'
        [IO.File]::WriteAllBytes($wrap, $gbk.GetBytes(($lines -join "`r`n") + "`r`n"))
        $o = & $env:ComSpec /c "`"$wrap`"" 2>&1 | Out-String
        [pscustomobject]@{ Code = $LASTEXITCODE; Text = $o }
    }
    $entry = Join-Path $inst 'Multisim兼容启动.cmd'
    $env:MSCOMPAT_NOPAUSE = '1'
    if (-not $SkipMachine) {
        $r = Run-Cmd $entry '/check'
        Ok ($r.Code -eq 0) 'cmd /check 在本机真实 Multisim 14.0.593 上全部通过（未启动 Multisim）'
        # 篡改运行时文件 -> 必须拒绝
        $lp = Join-Path $inst 'runtime\locale-emulator\LoaderDll.dll'
        $orig = [IO.File]::ReadAllBytes($lp)
        [IO.File]::WriteAllBytes($lp, $orig + [byte[]](0x00))
        $r2 = Run-Cmd $entry '/check'
        Ok ($r2.Code -ne 0) '运行时文件被改动 => cmd 拒绝启动'
        $r3 = Run-Cmd $entry '/check' @{ MSCOMPAT_ALLOW_CUSTOM_RUNTIME = '1' }
        Ok ($r3.Code -eq 0) 'MSCOMPAT_ALLOW_CUSTOM_RUNTIME=1 时只警告（LGPL 允许替换）'
        [IO.File]::WriteAllBytes($lp, $orig)
        # 目标旁有 .le.config -> 必须拒绝（用临时副本，不碰 NI 目录）
        $ni = Split-Path -Parent (Get-Content -LiteralPath (Join-Path $inst 'config\multisim-path.txt') -Encoding Default | Select-Object -First 1)
        $copy = Join-Path $tmp 'nicopy'
        [void](New-Item -ItemType Directory -Path $copy)
        foreach ($n in 'multisim.exe', 'LibraryAccess.dll', 'WidgetLibrary.dll') { Copy-Item -LiteralPath (Join-Path $ni $n) -Destination $copy }
        [IO.File]::WriteAllText((Join-Path $copy 'multisim.exe.le.config'), '')
        $pf = Join-Path $inst 'config\multisim-path.txt'
        $pfOrig = [IO.File]::ReadAllBytes($pf)
        [IO.File]::WriteAllBytes($pf, $gbk.GetBytes((Join-Path $copy 'multisim.exe') + "`r`n"))
        $r4 = Run-Cmd $entry '/check'
        Ok ($r4.Code -ne 0) '目标旁有 multisim.exe.le.config => cmd 拒绝启动'
        # 未知构建 -> 必须拒绝
        $gp = Join-Path $inst 'config\cmd-gate.txt'
        $gorig = [IO.File]::ReadAllBytes($gp)
        [IO.File]::WriteAllBytes($pf, $pfOrig)
        [IO.File]::WriteAllText($gp, (([IO.File]::ReadAllText($gp) -replace '(?m)^B,[0-9A-F]{64}', ('B,' + ('0' * 64)))), $utf8)
        $r5 = Run-Cmd $entry '/check'
        Ok ($r5.Code -ne 0) '三文件哈希不在白名单 => cmd 拒绝启动'
        [IO.File]::WriteAllBytes($gp, $gorig)
    } else { Write-Host '[跳过] 本机集成（cmd /check 对真实 Multisim 的检查）' }

    # 卸载演练：先拒绝非安装目录，再真正卸载
    $fake = Join-Path $tmp 'notours'
    [void](New-Item -ItemType Directory -Path $fake)
    Copy-Item -LiteralPath (Join-Path $inst '卸载.cmd') -Destination (Join-Path $fake '卸载.cmd')
    [IO.File]::WriteAllText((Join-Path $fake 'keep.txt'), 'x')
    $r6 = Run-Cmd (Join-Path $fake '卸载.cmd') '/y'
    Ok ($r6.Code -ne 0 -and (Test-Path -LiteralPath (Join-Path $fake 'keep.txt'))) '卸载.cmd 在非安装目录里拒绝删除任何东西'
    $r7 = Run-Cmd (Join-Path $inst '卸载.cmd') '/y'
    for ($i = 0; $i -lt 30 -and (Test-Path -LiteralPath $inst); $i++) { Start-Sleep -Milliseconds 500 }
    Ok (-not (Test-Path -LiteralPath $inst)) '卸载.cmd /y 删除安装目录（含自身）'
    Ok (Test-Path -LiteralPath (Join-Path $tmp 'dist')) '卸载只删安装目录，不波及同级其他文件'
}
finally {
    Remove-Item Env:\MSCOMPAT_NOPAUSE -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

# ---- 8. 本机只读集成 --------------------------------------------------------------------------
if (-not $SkipMachine) {
    $found = @(Find-MultisimInstallation)
    if ($found.Count -gt 0) {
        $rep = Get-MultisimCompatibilityReport -Installation $found[0] -RepositoryRoot $root
        Ok ($rep.Disposition.State -eq 'Verified') "本机 Multisim 构建判定为 Verified（实际：$($rep.Disposition.State)）"
        Ok ($rep.Blockers.Count -eq 0) ("本机没有启动阻断项" + $(if ($rep.Blockers.Count) { '：' + ($rep.Blockers -join '；') } else { '' }))
    } else { Write-Host '[跳过] 本机未安装 Multisim 14.x' }
}

Write-Host ''
Write-Host "通过：$script:Pass；失败：$script:Fail"
if ($script:Fail -gt 0) { exit 1 }
