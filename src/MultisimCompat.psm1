Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# SPDX-FileCopyrightText: 2026 multisimcompatfix contributors
# SPDX-License-Identifier: MIT

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function ConvertTo-NormalizedVersion {
    param([AllowNull()][AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [version]'0.0.0.0'
    }
    $match = [regex]::Match($Value, '\d+(?:\.\d+){1,3}')
    if (-not $match.Success) {
        return [version]'0.0.0.0'
    }
    $parts = @($match.Value.Split('.'))
    while ($parts.Count -lt 4) {
        $parts += '0'
    }
    [version]($parts[0..3] -join '.')
}

function Get-PeArchitecture {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        $reader = [IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            return 'NotPE'
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 0 -or $peOffset -gt ($stream.Length - 6)) {
            return 'NotPE'
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            return 'NotPE'
        }
        switch ($reader.ReadUInt16()) {
            0x014C { 'x86' }
            0x8664 { 'x64' }
            0x01C0 { 'ARM' }
            0xAA64 { 'ARM64' }
            default { 'Other' }
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-JetHeaderMarker {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        if ($stream.Length -lt 21) {
            return $null
        }
        $stream.Position = 0x14
        $stream.ReadByte()
    }
    finally {
        $stream.Dispose()
    }
}

function Import-SupportManifest {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)
    $path = Join-Path $RepositoryRoot 'config\support-manifest.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "缺少支持清单：$path"
    }
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Find-MultisimInstallation {
    [CmdletBinding()]
    param()

    $registryRoot = 'HKLM:\SOFTWARE\WOW6432Node\National Instruments\Circuit Design Suite'
    if (-not (Test-Path -LiteralPath $registryRoot)) {
        return @()
    }

    $results = @()
    foreach ($versionKey in @(Get-ChildItem -LiteralPath $registryRoot -ErrorAction SilentlyContinue)) {
        if ($versionKey.PSChildName -notmatch '^14\.[0-3]$') {
            continue
        }
        $commonKey = Join-Path $versionKey.PSPath 'Common'
        $coreKey = Join-Path $versionKey.PSPath 'MSI Parts\Core'
        $installRoot = $null
        if (Test-Path -LiteralPath $coreKey) {
            $installRoot = (Get-ItemProperty -LiteralPath $coreKey -ErrorAction SilentlyContinue).Path
        }
        if (-not $installRoot -and (Test-Path -LiteralPath $commonKey)) {
            $installRoot = (Get-ItemProperty -LiteralPath $commonKey -ErrorAction SilentlyContinue).Plugins
        }
        if (-not $installRoot) {
            continue
        }
        $path = Join-Path $installRoot 'multisim.exe'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }
        $results += [pscustomobject]@{
            VersionKey = $versionKey.PSChildName
            RegistryRoot = $versionKey.PSPath
            CommonKey = $commonKey
            InstallRoot = (Resolve-Path -LiteralPath $installRoot).Path
            MultisimPath = (Resolve-Path -LiteralPath $path).Path
        }
    }
    @($results | Sort-Object MultisimPath -Unique)
}

function Resolve-MultisimInstallation {
    param([AllowNull()][string]$MultisimPath)

    $installations = @(Find-MultisimInstallation)
    if ([string]::IsNullOrWhiteSpace($MultisimPath)) {
        return $installations
    }
    if (-not (Test-Path -LiteralPath $MultisimPath -PathType Leaf)) {
        throw "Multisim 不存在：$MultisimPath"
    }
    $resolved = (Resolve-Path -LiteralPath $MultisimPath).Path
    $match = @($installations | Where-Object { $_.MultisimPath -eq $resolved })
    if ($match.Count -eq 1) {
        return $match
    }

    $item = Get-Item -LiteralPath $resolved
    $productVersion = ConvertTo-NormalizedVersion $item.VersionInfo.ProductVersion
    $versionKey = '{0}.{1}' -f $productVersion.Major, $productVersion.Minor
    $registryRoot = "HKLM:\SOFTWARE\WOW6432Node\National Instruments\Circuit Design Suite\$versionKey"
    [pscustomobject]@{
        VersionKey = $versionKey
        RegistryRoot = $registryRoot
        CommonKey = Join-Path $registryRoot 'Common'
        InstallRoot = Split-Path -Parent $resolved
        MultisimPath = $resolved
    }
}

function Get-NiSignatureState {
    param([Parameter(Mandatory = $true)][string]$Path)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    $subject = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { '' }
    [pscustomobject]@{
        Status = [string]$signature.Status
        Subject = $subject
        IsNationalInstruments = ($signature.Status -eq 'Valid' -and $subject -match 'National Instruments|\bNI\b')
    }
}

function Get-SystemCompatibilityState {
    $osVersion = [Environment]::OSVersion.Version
    $languageKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language'
    $installLanguage = ''
    if (Test-Path -LiteralPath $languageKey) {
        $installLanguage = [string](Get-ItemProperty -LiteralPath $languageKey).InstallLanguage
    }
    $systemLocale = ''
    try {
        $systemLocale = (Get-WinSystemLocale).Name
    }
    catch {
        $systemLocale = [Globalization.CultureInfo]::CurrentCulture.Name
    }
    $nativeChineseCodes = @('0004', '0404', '0804', '0C04', '1004', '1404', '7C04')
    $nativeChinese = $installLanguage.ToUpperInvariant() -in $nativeChineseCodes
    $systemChinese = $systemLocale -match '^zh(?:-|$)'
    $isWindows11 = $osVersion.Build -ge 22000
    $is24H2OrLater = $osVersion.Build -ge 26100
    [pscustomobject]@{
        Version = $osVersion.ToString()
        Build = $osVersion.Build
        InstallLanguage = $installLanguage
        SystemLocale = $systemLocale
        NativeChinese = $nativeChinese
        SystemLocaleChinese = $systemChinese
        IsWindows11 = $isWindows11
        Is24H2OrLater = $is24H2OrLater
        MatchesKnownIssue = ($isWindows11 -and $is24H2OrLater -and $nativeChinese -and $systemChinese)
    }
}

function Get-DaoCompatibilityState {
    $progIdPath = 'Registry::HKEY_CLASSES_ROOT\DAO.DBEngine.36\CLSID'
    $clsid = ''
    if (Test-Path -LiteralPath $progIdPath) {
        $clsid = [string](Get-Item -LiteralPath $progIdPath).GetValue('')
    }
    $inprocPath = if ($clsid) { "Registry::HKEY_CLASSES_ROOT\WOW6432Node\CLSID\$clsid\InprocServer32" } else { '' }
    $rawDaoPath = ''
    if ($inprocPath -and (Test-Path -LiteralPath $inprocPath)) {
        $rawDaoPath = [string](Get-Item -LiteralPath $inprocPath).GetValue(
            '',
            $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
        )
    }
    $commonX86 = [Environment]::GetEnvironmentVariable('CommonProgramFiles(x86)', 'Machine')
    if (-not $commonX86) {
        $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)', 'Machine')
        if ($programFilesX86) {
            $commonX86 = Join-Path $programFilesX86 'Common Files'
        }
    }
    if (-not $commonX86) {
        $windowsPathsKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion'
        if (Test-Path -LiteralPath $windowsPathsKey) {
            $commonX86 = [string](Get-ItemProperty -LiteralPath $windowsPathsKey).'CommonFilesDir (x86)'
        }
    }
    $daoPath = $rawDaoPath
    if ($daoPath -and $commonX86) {
        $daoPath = $daoPath -ireplace [regex]::Escape('%CommonProgramFiles%'), $commonX86
    }
    if ($daoPath) {
        $daoPath = [Environment]::ExpandEnvironmentVariables($daoPath)
    }
    $jetKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Jet\4.0\Engines\Jet 4.0'
    [pscustomobject]@{
        Clsid = $clsid
        DaoPath = $daoPath
        DaoRegistered = [bool]$clsid
        DaoFileExists = [bool]($daoPath -and (Test-Path -LiteralPath $daoPath -PathType Leaf))
        JetRegistryExists = Test-Path -LiteralPath $jetKey
        CommonProgramFilesX86 = $commonX86
        Ready = ([bool]$clsid -and [bool]($daoPath -and (Test-Path -LiteralPath $daoPath -PathType Leaf)) -and (Test-Path -LiteralPath $jetKey))
    }
}

function Get-DatabaseCompatibilityState {
    param([Parameter(Mandatory = $true)]$Installation)

    $records = @()
    if (-not (Test-Path -LiteralPath $Installation.CommonKey)) {
        return [pscustomobject]@{
            RegistryKeyExists = $false
            Files = @()
            AllFilesPresent = $false
            LegacyCount = 0
            MatchesKnownIssue = $false
        }
    }
    $properties = Get-ItemProperty -LiteralPath $Installation.CommonKey
    $mapping = @(
        @{ Name = 'Master'; Property = 'Database_Master' },
        @{ Name = 'Corporate'; Property = 'Database_Corporate' },
        @{ Name = 'UserTemplate'; Property = 'Database_UserTemplate' }
    )
    foreach ($entry in $mapping) {
        $path = [string]$properties.($entry.Property)
        $exists = [bool]($path -and (Test-Path -LiteralPath $path -PathType Leaf))
        $marker = $null
        $readError = ''
        if ($exists) {
            try {
                $marker = Get-JetHeaderMarker $path
            }
            catch {
                $readError = $_.Exception.Message
            }
        }
        $records += [pscustomobject]@{
            Name = $entry.Name
            Path = $path
            Exists = $exists
            Marker = $marker
            IsLegacy = ($marker -eq 0)
            ReadError = $readError
        }
    }
    $allPresent = @($records | Where-Object { -not $_.Exists -or $_.ReadError }).Count -eq 0
    $legacyCount = @($records | Where-Object IsLegacy).Count
    [pscustomobject]@{
        RegistryKeyExists = $true
        Files = $records
        AllFilesPresent = $allPresent
        LegacyCount = $legacyCount
        MatchesKnownIssue = ($allPresent -and $legacyCount -gt 0)
    }
}

function Get-RuntimeCompatibilityState {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)]$Manifest,
        [AllowNull()][string]$RuntimeRoot
    )
    if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) {
        $RuntimeRoot = Join-Path $RepositoryRoot 'runtime\locale-emulator'
    }
    $files = @()
    foreach ($entry in @($Manifest.RuntimeFiles)) {
        $path = Join-Path $RuntimeRoot $entry.Path
        $exists = Test-Path -LiteralPath $path -PathType Leaf
        $actual = if ($exists) { Get-FileSha256 $path } else { '' }
        $files += [pscustomobject]@{
            Name = $entry.Path
            Path = $path
            Exists = $exists
            ExpectedSha256 = [string]$entry.Sha256
            ActualSha256 = $actual
            HashMatches = ($exists -and $actual -eq [string]$entry.Sha256)
        }
    }
    $forbidden = @()
    foreach ($name in @($Manifest.ForbiddenRuntimeFiles)) {
        $path = Join-Path $RuntimeRoot $name
        if (Test-Path -LiteralPath $path) {
            $forbidden += $path
        }
    }
    $configPath = Join-Path $RuntimeRoot 'LEConfig.xml'
    $configValid = $false
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        try {
            [xml]$config = Get-Content -LiteralPath $configPath -Raw
            $profiles = @($config.LEConfig.Profiles.Profile)
            $expectedGuid = [string]$Manifest.RuntimePackage.ProfileGuid
            $configValid = ($profiles.Count -eq 1 -and $profiles[0].Location -eq 'en-US' -and $profiles[0].RunAsAdmin -eq 'false' -and $profiles[0].RedirectRegistry -eq 'true' -and $profiles[0].Guid -eq $expectedGuid)
        }
        catch {
            $configValid = $false
        }
    }
    $coreX86 = $false
    $corePaths = @('LEProc.exe', 'LoaderDll.dll', 'LocaleEmulator.dll') | ForEach-Object { Join-Path $RuntimeRoot $_ }
    if (@($corePaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -eq 0) {
        $coreX86 = @($corePaths | Where-Object { (Get-PeArchitecture $_) -ne 'x86' }).Count -eq 0
    }
    [pscustomobject]@{
        Root = $RuntimeRoot
        ProfileGuid = [string]$Manifest.RuntimePackage.ProfileGuid
        Files = $files
        ForbiddenFiles = $forbidden
        ConfigPath = $configPath
        ConfigValid = $configValid
        CoreX86 = $coreX86
        Valid = (@($files | Where-Object { -not $_.HashMatches }).Count -eq 0 -and $forbidden.Count -eq 0 -and $configValid -and $coreX86)
    }
}

function Get-BuildDisposition {
    param(
        [Parameter(Mandatory = $true)][version]$ProductVersion,
        [Parameter(Mandatory = $true)][version]$FileVersion,
        [Parameter(Mandatory = $true)][string]$MultisimSha256,
        [Parameter(Mandatory = $true)][version]$LibraryAccessVersion,
        [Parameter(Mandatory = $true)][string]$LibraryAccessSha256,
        [Parameter(Mandatory = $true)][string]$WidgetLibrarySha256,
        [Parameter(Mandatory = $true)]$Manifest
    )
    $verified = @($Manifest.VerifiedBuilds | Where-Object {
        (ConvertTo-NormalizedVersion $_.ProductVersion) -eq $ProductVersion -and
        (ConvertTo-NormalizedVersion $_.FileVersion) -eq $FileVersion -and
        ([string]$_.MultisimSha256).ToUpperInvariant() -eq $MultisimSha256 -and
        ([string]$_.LibraryAccessSha256).ToUpperInvariant() -eq $LibraryAccessSha256 -and
        ([string]$_.WidgetLibrarySha256).ToUpperInvariant() -eq $WidgetLibrarySha256
    })
    if ($verified.Count -eq 1) {
        return [pscustomobject]@{ State = 'Verified'; Reason = $verified[0].Name }
    }

    $knownFixed = @($Manifest.KnownFixedLibraryAccess | Where-Object { ([string]$_.Sha256).ToUpperInvariant() -eq $LibraryAccessSha256 })
    $fixedMinimum = ConvertTo-NormalizedVersion $Manifest.FixedLibraryAccessMinimumFileVersion
    if ($ProductVersion.Major -eq 14 -and $ProductVersion.Minor -eq 3 -and ($knownFixed.Count -gt 0 -or $LibraryAccessVersion -ge $fixedMinimum)) {
        return [pscustomobject]@{ State = 'OfficialFixAvailable'; Reason = '检测到 14.3.3 或更高的数据库访问组件' }
    }

    $candidateMinor = @($Manifest.CandidateMinorVersions | ForEach-Object { [int]$_ })
    if ($ProductVersion.Major -eq [int]$Manifest.SupportedProductMajor -and $ProductVersion.Minor -in $candidateMinor) {
        return [pscustomobject]@{ State = 'Candidate'; Reason = '版本属于 14.0–14.3.2 候选范围，但该精确构建尚未验证' }
    }
    [pscustomobject]@{ State = 'Unsupported'; Reason = '版本不在支持范围' }
}

function Get-MultisimCompatibilityReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Installation,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )
    $manifest = Import-SupportManifest $RepositoryRoot
    $target = $Installation.MultisimPath
    $installRoot = Split-Path -Parent $target
    $libraryAccessPath = Join-Path $installRoot 'LibraryAccess.dll'
    $widgetLibraryPath = Join-Path $installRoot 'WidgetLibrary.dll'
    $blockers = @()
    $warnings = @()

    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        throw "Multisim 不存在：$target"
    }
    if (-not (Test-Path -LiteralPath $libraryAccessPath -PathType Leaf)) {
        $blockers += "缺少 LibraryAccess.dll：$libraryAccessPath"
    }
    if (-not (Test-Path -LiteralPath $widgetLibraryPath -PathType Leaf)) {
        $blockers += "缺少 WidgetLibrary.dll：$widgetLibraryPath"
    }

    $item = Get-Item -LiteralPath $target
    $productVersion = ConvertTo-NormalizedVersion $item.VersionInfo.ProductVersion
    $fileVersion = ConvertTo-NormalizedVersion $item.VersionInfo.FileVersion
    $architecture = Get-PeArchitecture $target
    $signature = Get-NiSignatureState $target
    $multisimHash = Get-FileSha256 $target

    $libraryVersion = [version]'0.0.0.0'
    $libraryHash = ''
    if (Test-Path -LiteralPath $libraryAccessPath -PathType Leaf) {
        $libraryItem = Get-Item -LiteralPath $libraryAccessPath
        $libraryVersion = ConvertTo-NormalizedVersion $libraryItem.VersionInfo.FileVersion
        $libraryHash = Get-FileSha256 $libraryAccessPath
    }
    $widgetHash = if (Test-Path -LiteralPath $widgetLibraryPath -PathType Leaf) { Get-FileSha256 $widgetLibraryPath } else { '' }
    $disposition = Get-BuildDisposition -ProductVersion $productVersion -FileVersion $fileVersion -MultisimSha256 $multisimHash -LibraryAccessVersion $libraryVersion -LibraryAccessSha256 $libraryHash -WidgetLibrarySha256 $widgetHash -Manifest $manifest
    $system = Get-SystemCompatibilityState
    $database = Get-DatabaseCompatibilityState $Installation
    $dao = Get-DaoCompatibilityState
    $runtime = Get-RuntimeCompatibilityState -RepositoryRoot $RepositoryRoot -Manifest $manifest
    $sidecar = "$target.le.config"
    $running = @(Get-Process -Name 'multisim' -ErrorAction SilentlyContinue)

    if ($architecture -ne 'x86') { $blockers += "仅支持 x86 Multisim；实际为 $architecture" }
    if (-not $signature.IsNationalInstruments) { $blockers += "multisim.exe 没有可验证的 National Instruments 签名：$($signature.Status)" }
    if ($disposition.State -eq 'Unsupported') { $blockers += $disposition.Reason }
    if ($disposition.State -eq 'OfficialFixAvailable') { $blockers += '该安装已包含 NI 官方数据库修复，不应使用兼容层。' }
    if (-not $system.MatchesKnownIssue) { $blockers += '系统不符合 Windows 11 24H2+、中文原生安装且系统区域为中文的已知故障画像。' }
    if (-not $database.RegistryKeyExists) { $blockers += "缺少 NI Common 注册表配置：$($Installation.CommonKey)" }
    elseif (-not $database.AllFilesPresent) { $blockers += '主库、企业库或用户库模板缺失或不可读。' }
    elseif (-not $database.MatchesKnownIssue) { $blockers += '数据库头未显示旧式 Jet 标记，不能证明与已知问题匹配。' }
    if (-not $dao.Ready) { $blockers += '32 位 DAO 3.6 / Jet 4.0 依赖不完整；应先修复依赖而不是使用兼容层。' }
    if (-not $runtime.Valid) { $blockers += '兼容运行时缺失或校验失败；请重新运行安装脚本修复。' }
    if (Test-Path -LiteralPath $sidecar) { $blockers += "目标旁存在会覆盖隔离配置的文件：$sidecar" }
    if ($running.Count -gt 0) { $blockers += 'Multisim 已在运行。' }

    $nonAsciiPaths = @((@($target) + @($database.Files | ForEach-Object Path)) | Where-Object { $_ -and $_ -match '[^\x00-\x7F]' })
    if ($nonAsciiPaths.Count -gt 0) {
        $warnings += '检测到包含非 ASCII 字符的程序或数据库路径；en-US/CP1252 环境下必须额外验证。'
    }
    $warnings += '兼容进程界面将显示为英文；中文工程路径、模型路径和文本尚需逐版本验证。'
    if ($disposition.State -eq 'Candidate') {
        $warnings += '候选构建需要 -AllowCandidateBuild 与 -ConfirmDatabaseError 双重显式确认。'
    }

    [pscustomobject]@{
        Target = $target
        VersionKey = $Installation.VersionKey
        ProductVersion = $productVersion.ToString()
        FileVersion = $fileVersion.ToString()
        Architecture = $architecture
        Sha256 = $multisimHash
        Signature = $signature
        LibraryAccess = [pscustomobject]@{ Path = $libraryAccessPath; Version = $libraryVersion.ToString(); Sha256 = $libraryHash }
        WidgetLibrary = [pscustomobject]@{ Path = $widgetLibraryPath; Sha256 = $widgetHash }
        Disposition = $disposition
        System = $system
        Database = $database
        Dao = $dao
        Runtime = $runtime
        SidecarConfig = $sidecar
        Blockers = $blockers
        Warnings = $warnings
        CanStartVerified = ($blockers.Count -eq 0 -and $disposition.State -eq 'Verified')
        CanStartCandidate = ($blockers.Count -eq 0 -and $disposition.State -eq 'Candidate')
    }
}

function Start-MultisimWithCompatibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Report,
        [switch]$AllowCandidateBuild,
        [switch]$ConfirmDatabaseError
    )
    if ($Report.Blockers.Count -gt 0) {
        throw "存在阻断项，拒绝启动：$($Report.Blockers -join '；')"
    }
    if ($Report.Disposition.State -eq 'Candidate' -and (-not $AllowCandidateBuild -or -not $ConfirmDatabaseError)) {
        throw '候选构建必须同时指定 -AllowCandidateBuild 和 -ConfirmDatabaseError。'
    }
    if ($Report.Disposition.State -notin @('Verified', 'Candidate')) {
        throw "构建状态不允许启动：$($Report.Disposition.State)"
    }
    $leProc = Join-Path $Report.Runtime.Root 'LEProc.exe'
    $commonX86 = $Report.Dao.CommonProgramFilesX86
    if (-not $commonX86) {
        throw '无法解析 32 位 Common Files 目录。'
    }
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $profileGuid = [string]$Report.Runtime.ProfileGuid
    if ($profileGuid -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') {
        throw "支持清单里的 Locale Emulator 配置 GUID 无效：$profileGuid"
    }
    $startInfo.FileName = $leProc
    $startInfo.Arguments = '-runas {0} "{1}"' -f $profileGuid, $Report.Target
    $startInfo.WorkingDirectory = $Report.Runtime.Root
    $startInfo.UseShellExecute = $false
    $startInfo.EnvironmentVariables['CommonProgramFiles'] = $commonX86
    $process = [Diagnostics.Process]::Start($startInfo)
    if ($null -eq $process) {
        throw 'Locale Emulator 启动失败。'
    }
    [pscustomobject]@{ LeProcPid = $process.Id; Target = $Report.Target; Disposition = $Report.Disposition.State }
}

function New-MultisimCompatibleShortcut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$EntryScript,
        [Parameter(Mandatory = $true)]$Report,
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$AllowCandidateBuild,
        [switch]$ConfirmDatabaseError,
        [switch]$Force
    )
    if ($Name -match '[\\/:*?"<>|]') {
        throw '快捷方式名称包含非法字符。'
    }
    if ($Report.Disposition.State -ne 'Verified') {
        throw '双击入口 .cmd 只启动已验证构建；候选构建请用 multisim-compat.ps1 -Action Start 显式启动。'
    }
    if ($Report.Blockers.Count -gt 0) {
        throw "存在阻断项，拒绝创建快捷方式：$($Report.Blockers -join '；')"
    }
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop ($Name + '.lnk')
    if ((Test-Path -LiteralPath $shortcutPath) -and -not $Force) {
        throw "快捷方式已存在；未覆盖：$shortcutPath"
    }
    # 快捷方式直接指向双击入口 .cmd，不经过 PowerShell，也就不受 ExecutionPolicy 影响。
    if (-not (Test-Path -LiteralPath $EntryScript -PathType Leaf) -or [IO.Path]::GetExtension($EntryScript) -ne '.cmd') {
        throw "快捷方式入口必须是存在的 .cmd 文件：$EntryScript"
    }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $EntryScript
    $shortcut.Arguments = ''
    $shortcut.WorkingDirectory = Split-Path -Parent $EntryScript
    $shortcut.IconLocation = "$($Report.Target),0"
    $shortcut.Description = 'Unofficial compatibility launcher for a locally licensed NI Multisim installation'
    $shortcut.WindowStyle = 7
    $shortcut.Save()
    if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
        throw '快捷方式保存失败。'
    }
    $shortcutPath
}

function Remove-MultisimCompatibleShortcut {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Name)
    if ($Name -match '[\\/:*?"<>|]') {
        throw '快捷方式名称包含非法字符。'
    }
    $path = Join-Path ([Environment]::GetFolderPath('Desktop')) ($Name + '.lnk')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ Path = $path; Removed = $false; Reason = '不存在' }
    }
    Remove-Item -LiteralPath $path
    [pscustomobject]@{ Path = $path; Removed = (-not (Test-Path -LiteralPath $path)); Reason = '已删除' }
}

Export-ModuleMember -Function @(
    'Get-FileSha256',
    'ConvertTo-NormalizedVersion',
    'Get-PeArchitecture',
    'Get-JetHeaderMarker',
    'Import-SupportManifest',
    'Find-MultisimInstallation',
    'Resolve-MultisimInstallation',
    'Get-SystemCompatibilityState',
    'Get-DaoCompatibilityState',
    'Get-DatabaseCompatibilityState',
    'Get-RuntimeCompatibilityState',
    'Get-BuildDisposition',
    'Get-MultisimCompatibilityReport',
    'Start-MultisimWithCompatibility',
    'New-MultisimCompatibleShortcut',
    'Remove-MultisimCompatibleShortcut'
)
