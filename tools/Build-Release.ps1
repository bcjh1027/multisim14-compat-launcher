# SPDX-License-Identifier: MIT
# 构建发布包 dist\：
#   MultisimCompat-<版本>.zip          安装包（含 Locale Emulator 运行时，LGPL 源码另附）
#   install.ps1                        写入版本号和 zip 的 SHA-256 后的安装脚本
#   Locale-Emulator-*-source.zip       LGPL 对应源码（与 zip 同一 Release 一并上传）
#   SHA256SUMS.txt
# 不会联网，不会修改仓库内容。
[CmdletBinding()]
param(
    [string]$Version,
    [string]$OutDir,
    [switch]$RegenerateGate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $Version) { $Version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim() }
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "版本号格式应为 x.y.z：$Version" }
if (-not $OutDir) { $OutDir = Join-Path $root 'dist' }
Import-Module (Join-Path $root 'src\MultisimCompat.psm1') -Force

$manifest = Import-SupportManifest $root
$runtimeSrc = Join-Path $root 'runtime\locale-emulator'
$utf8 = [Text.UTF8Encoding]::new($false)

function Assert-Hash([string]$Path, [string]$Expected, [string]$What) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "缺少$What：$Path" }
    $got = Get-FileSha256 $Path
    if ($got -ne $Expected.ToUpperInvariant()) { throw "$What 的 SHA-256 不符：期望 $Expected，实际 $got" }
}

# ---- 1. 第三方文件逐个核对 ------------------------------------------------------------------
$state = Get-RuntimeCompatibilityState -RepositoryRoot $root -Manifest $manifest -RuntimeRoot $runtimeSrc
if (-not $state.Valid) { throw 'runtime\locale-emulator 校验失败（哈希/架构/配置/禁止文件）。' }
$pkg = $manifest.RuntimePackage
$lePkgSrc = Join-Path $root 'vendor\locale-emulator\Locale-Emulator-2.5.0.1-source.zip'
$leCoreSrc = Join-Path $root 'vendor\locale-emulator-core\Locale-Emulator-Core-ae7160d-source.zip'
Assert-Hash $lePkgSrc $pkg.SourceSha256 'Locale Emulator 主仓库源码包'
Assert-Hash $leCoreSrc $pkg.CoreSourceSha256 'Locale-Emulator-Core 源码包'
Assert-Hash (Join-Path $root 'vendor\locale-emulator\Locale.Emulator.2.5.0.1.zip') $pkg.ReleaseSha256 'Locale Emulator 官方发布包'

# ---- 2. 生成 cmd 用的哈希白名单，并检查仓库里的副本与清单一致 -----------------------------------
$gate = [Collections.Generic.List[string]]::new()
$gate.Add('# 双击入口 Multisim兼容启动.cmd 使用的哈希白名单（纯 cmd 无法解析 JSON）。')
$gate.Add('# 由 tools\Build-Release.ps1 依据 config\support-manifest.json 生成；tests\Run-Tests.ps1 校验两者一致。')
$gate.Add('# B,<multisim.exe>,<LibraryAccess.dll>,<WidgetLibrary.dll>,<名称>')
$gate.Add('# R,<sha256>,<运行时文件名>')
foreach ($b in @($manifest.VerifiedBuilds)) {
    $gate.Add(('B,{0},{1},{2},{3}' -f $b.MultisimSha256.ToUpperInvariant(), $b.LibraryAccessSha256.ToUpperInvariant(), $b.WidgetLibrarySha256.ToUpperInvariant(), $b.Name))
}
foreach ($f in @($manifest.RuntimeFiles)) {
    $gate.Add(('R,{0},{1}' -f $f.Sha256.ToUpperInvariant(), $f.Path))
}
# LEConfig.xml 决定 Multisim 拿到哪个区域，所以也锁定哈希（文件由本项目维护，不在 RuntimeFiles 里）
$gate.Add(('R,{0},LEConfig.xml' -f (Get-FileSha256 (Join-Path $root 'config\locale-emulator\LEConfig.xml'))))
$gateText = ($gate -join "`r`n") + "`r`n"
$gateRepo = Join-Path $root 'config\cmd-gate.txt'
$gateLf = ($gateText -replace "`r`n", "`n")
if ($RegenerateGate) {
    [IO.File]::WriteAllText($gateRepo, $gateLf, $utf8)
    Write-Host "已重新生成 $gateRepo"
    return
}
$gateRepoText = [IO.File]::ReadAllText($gateRepo, $utf8) -replace "`r`n", "`n"
if ($gateRepoText.TrimEnd() -ne $gateLf.TrimEnd()) {
    throw 'config\cmd-gate.txt 与 support-manifest.json 不一致；请运行 tools\Build-Release.ps1 -RegenerateGate 后提交。'
}

# ---- 3. 暂存目录 -----------------------------------------------------------------------------
$work = Join-Path ([IO.Path]::GetTempPath()) ('mscompat-build-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $work 'MultisimCompat'
[void](New-Item -ItemType Directory -Path $stage -Force)
try {
    function Copy-Into([string]$RelFrom, [string]$RelTo) {
        $dst = Join-Path $stage $RelTo
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force)
        Copy-Item -LiteralPath (Join-Path $root $RelFrom) -Destination $dst
    }
    # 文本文件统一 CRLF，便于记事本查看
    function Copy-TextCrlf([string]$RelFrom, [string]$RelTo, [bool]$Bom) {
        $text = [IO.File]::ReadAllText((Join-Path $root $RelFrom), $utf8) -replace "`r`n", "`n" -replace "`n", "`r`n"
        $dst = Join-Path $stage $RelTo
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force)
        [IO.File]::WriteAllText($dst, $text, [Text.UTF8Encoding]::new($Bom))
    }
    # cmd：UTF-8 源 -> GBK + CRLF。无法用 GBK 表示的字符直接报错，不静默替换。
    $gbk = [Text.Encoding]::GetEncoding(936, [Text.EncoderExceptionFallback]::new(), [Text.DecoderExceptionFallback]::new())
    function Convert-Cmd([string]$RelFrom, [string]$NameTo) {
        $text = [IO.File]::ReadAllText((Join-Path $root $RelFrom), $utf8)
        $text = $text -replace "`r`n", "`n" -replace "`n", "`r`n"
        try { $bytes = $gbk.GetBytes($text) } catch { throw "$RelFrom 含有 GBK 无法表示的字符：$($_.Exception.Message)" }
        [IO.File]::WriteAllBytes((Join-Path $stage $NameTo), $bytes)
    }
    Convert-Cmd 'src\cmd\launch.cmd.utf8'    'Multisim兼容启动.cmd'
    Convert-Cmd 'src\cmd\check.cmd.utf8'     'Multisim兼容检查.cmd'
    Convert-Cmd 'src\cmd\uninstall.cmd.utf8' '卸载.cmd'

    foreach ($p in 'src\MultisimCompat.psm1', 'src\WindowsPowerShellBootstrap.ps1') { Copy-TextCrlf $p $p $true }
    Copy-TextCrlf 'multisim-compat.ps1' 'multisim-compat.ps1' $true
    Copy-TextCrlf 'config\support-manifest.json' 'config\support-manifest.json' $false
    [IO.File]::WriteAllText((Join-Path $stage 'config\cmd-gate.txt'), $gateText, $utf8)
    Copy-Into 'config\locale-emulator\LEConfig.xml' 'config\locale-emulator\LEConfig.xml'

    foreach ($f in @($manifest.RuntimeFiles)) { Copy-Into ('runtime\locale-emulator\' + $f.Path) ('runtime\locale-emulator\' + $f.Path) }
    foreach ($n in 'LEConfig.xml', 'LICENSE-GPL-3.0.txt', 'LICENSE-LGPL-3.0.txt') { Copy-Into ('runtime\locale-emulator\' + $n) ('runtime\locale-emulator\' + $n) }
    # 运行时目录里的 LEConfig.xml 必须与仓库里受控的那份完全一致
    Assert-Hash (Join-Path $stage 'runtime\locale-emulator\LEConfig.xml') (Get-FileSha256 (Join-Path $root 'config\locale-emulator\LEConfig.xml')) 'LEConfig.xml'

    foreach ($n in 'LICENSE', 'LICENSE_SCOPE.md', 'THIRD_PARTY_NOTICES.md', 'README.md', 'CHANGELOG.md') {
        if (Test-Path -LiteralPath (Join-Path $root $n)) { Copy-TextCrlf $n $n $false }
    }
    foreach ($n in 'LICENSE-GPL-3.0.txt', 'LICENSE-LGPL-3.0.txt') { Copy-Into ('third_party\locale-emulator\' + $n) ('third_party\locale-emulator\' + $n) }
    foreach ($d in @(Get-ChildItem -LiteralPath (Join-Path $root 'docs') -Filter *.md -ErrorAction SilentlyContinue)) { Copy-TextCrlf ('docs\' + $d.Name) ('docs\' + $d.Name) $false }
    foreach ($d in @(Get-ChildItem -LiteralPath (Join-Path $root 'docs\evidence') -File -ErrorAction SilentlyContinue)) { Copy-Into ('docs\evidence\' + $d.Name) ('docs\evidence\' + $d.Name) }
    [IO.File]::WriteAllText((Join-Path $stage 'VERSION'), "$Version`r`n", $utf8)

    # 安装包里不能出现禁止组件，也不能有 NI 文件
    $forbidden = @('LEUpdater.exe', 'LEInstaller.exe', 'LEGUI.exe', 'multisim.exe', 'LibraryAccess.dll', 'WidgetLibrary.dll')
    $hits = @(Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object { $_.Name -in $forbidden })
    if ($hits.Count -gt 0) { throw "暂存目录含禁止文件：$($hits.FullName -join ', ')" }

    # ---- 4. 打 zip：标准 '/' 分隔、UTF-8 文件名、固定时间戳（可复现） -------------------------------
    if (Test-Path -LiteralPath $OutDir) { Remove-Item -LiteralPath $OutDir -Recurse -Force }
    [void](New-Item -ItemType Directory -Path $OutDir -Force)
    $zipName = "MultisimCompat-$Version.zip"
    $zipPath = Join-Path $OutDir $zipName
    $stamp = [DateTimeOffset]::new(2026, 10, 11, 0, 0, 0, [TimeSpan]::Zero)
    $fs = [IO.File]::Create($zipPath)
    try {
        # 不要传 entryNameEncoding：.NET Framework 只有在默认编码下才会给非 ASCII 文件名打 UTF-8 标志（bit 11），
        # 传了 UTF8 反而不打，中文系统上的读取方会按 GBK 解码成乱码。
        $zip = [IO.Compression.ZipArchive]::new($fs, [IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            $files = @(Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object { $_.FullName.Substring($stage.Length) } )
            foreach ($f in $files) {
                $rel = 'MultisimCompat/' + ($f.FullName.Substring($stage.Length + 1) -replace '\\', '/')
                $entry = $zip.CreateEntry($rel, [IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = $stamp
                $es = $entry.Open()
                try { $bytes = [IO.File]::ReadAllBytes($f.FullName); $es.Write($bytes, 0, $bytes.Length) } finally { $es.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $fs.Dispose() }
    $zipSha = Get-FileSha256 $zipPath

    # ---- 5. 盖章 install.ps1（无 BOM，原样 ASCII 主体） ------------------------------------------------
    $inst = [IO.File]::ReadAllText((Join-Path $root 'install.ps1'), $utf8)
    foreach ($token in '@@VERSION@@', '@@ZIPNAME@@', '@@ZIPSHA256@@') {
        if (-not $inst.Contains("'$token'")) { throw "install.ps1 缺少占位符 $token" }
    }
    $inst = $inst.Replace("'@@VERSION@@'", "'$Version'").Replace("'@@ZIPNAME@@'", "'$zipName'").Replace("'@@ZIPSHA256@@'", "'$zipSha'")
    $inst = $inst -replace "`r`n", "`n" -replace "`n", "`r`n"
    [IO.File]::WriteAllText((Join-Path $OutDir 'install.ps1'), $inst, $utf8)

    # ---- 6. LGPL 对应源码一并输出 --------------------------------------------------------------------
    Copy-Item -LiteralPath $lePkgSrc -Destination $OutDir
    Copy-Item -LiteralPath $leCoreSrc -Destination $OutDir

    $sums = Get-ChildItem -LiteralPath $OutDir -File | Where-Object Name -ne 'SHA256SUMS.txt' | Sort-Object Name | ForEach-Object { '{0} *{1}' -f (Get-FileSha256 $_.FullName).ToLowerInvariant(), $_.Name }
    [IO.File]::WriteAllText((Join-Path $OutDir 'SHA256SUMS.txt'), (($sums -join "`n") + "`n"), $utf8)

    Write-Host "构建完成：$OutDir"
    Get-ChildItem -LiteralPath $OutDir -File | ForEach-Object { '  {0,-48} {1,10:N0} 字节' -f $_.Name, $_.Length }
    Write-Host "zip SHA-256：$zipSha"
}
finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
