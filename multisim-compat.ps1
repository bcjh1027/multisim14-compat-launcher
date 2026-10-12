# SPDX-License-Identifier: MIT
# Multisim 14.x 兼容启动器：命令行入口（进阶用法）。
# 日常使用请直接双击「Multisim兼容启动.cmd」。本脚本提供：只读检查、安装列表、候选构建的显式启动、桌面快捷方式。
# 默认只检查，不启动、不修改任何东西。
[CmdletBinding()]
param(
    [ValidateSet('Inspect', 'List', 'Start', 'InstallShortcut', 'RemoveShortcut')]
    [string]$Action = 'Inspect',

    [string]$MultisimPath,

    [switch]$AllowCandidateBuild,

    [switch]$ConfirmDatabaseError,

    [string]$ShortcutName = 'Multisim 14.0 (兼容启动)',

    [switch]$Force,

    [switch]$Json
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$bootstrapPath = Join-Path $repositoryRoot 'src\WindowsPowerShellBootstrap.ps1'
$modulePath = Join-Path $repositoryRoot 'src\MultisimCompat.psm1'
if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) {
    throw "缺少 Windows PowerShell 引导脚本：$bootstrapPath"
}
. $bootstrapPath
Initialize-WindowsPowerShellModulePath
Import-Module $modulePath -Force

function Write-CompatibilityReport {
    param([Parameter(Mandatory = $true)]$Report)

    Write-Host '============================================================'
    Write-Host "目标：$($Report.Target)"
    Write-Host "版本：产品 $($Report.ProductVersion)；文件 $($Report.FileVersion)；架构 $($Report.Architecture)"
    Write-Host "构建状态：$($Report.Disposition.State) - $($Report.Disposition.Reason)"
    Write-Host "NI 签名：$($Report.Signature.Status)；$($Report.Signature.Subject)"
    Write-Host "系统：Windows build $($Report.System.Build)，安装语言 $($Report.System.InstallLanguage)，系统区域 $($Report.System.SystemLocale)"
    Write-Host "已知故障画像：$($Report.System.MatchesKnownIssue)"
    Write-Host "DAO/Jet：$($Report.Dao.Ready)；$($Report.Dao.DaoPath)"
    Write-Host "兼容运行时：$($Report.Runtime.Valid)"
    Write-Host '数据库：'
    foreach ($database in @($Report.Database.Files)) {
        Write-Host "  $($database.Name)：存在=$($database.Exists)，Jet 标记=$($database.Marker)，路径=$($database.Path)"
    }
    if ($Report.Blockers.Count -gt 0) {
        Write-Host '阻断项：'
        foreach ($blocker in $Report.Blockers) {
            Write-Host "  [阻断] $blocker"
        }
    }
    if ($Report.Warnings.Count -gt 0) {
        Write-Host '警告：'
        foreach ($warning in $Report.Warnings) {
            Write-Host "  [警告] $warning"
        }
    }
    Write-Host "可直接启动（已验证构建）：$($Report.CanStartVerified)；候选构建可确认启动：$($Report.CanStartCandidate)"
}

function Get-SelectedInstallation {
    $installations = @(Resolve-MultisimInstallation -MultisimPath $MultisimPath)
    if ($installations.Count -eq 0) {
        throw '没有发现 Multisim 14.0-14.3 安装。可使用 -MultisimPath 指定 multisim.exe。'
    }
    if ($installations.Count -gt 1 -and [string]::IsNullOrWhiteSpace($MultisimPath)) {
        throw '发现多个 Multisim 安装；请使用 -MultisimPath 明确选择。'
    }
    $installations[0]
}

switch ($Action) {
    'List' {
        $installations = @(Find-MultisimInstallation)
        if ($Json) {
            $installations | ConvertTo-Json -Depth 5
        }
        elseif ($installations.Count -eq 0) {
            Write-Host '没有发现 Multisim 14.0-14.3 安装。'
        }
        else {
            $installations | Format-Table VersionKey, MultisimPath, InstallRoot -AutoSize
        }
        exit 0
    }
    'RemoveShortcut' {
        $result = Remove-MultisimCompatibleShortcut -Name $ShortcutName
        if ($Json) { $result | ConvertTo-Json } else { $result | Format-List }
        exit 0
    }
}

$installation = Get-SelectedInstallation
$report = Get-MultisimCompatibilityReport -Installation $installation -RepositoryRoot $repositoryRoot

switch ($Action) {
    'Inspect' {
        if ($Json) {
            $report | ConvertTo-Json -Depth 10
        }
        else {
            Write-CompatibilityReport $report
            Write-Host ''
            Write-Host '默认仅检查，没有启动 Multisim，也没有修改系统、数据库或快捷方式。'
        }
    }
    'Start' {
        $result = Start-MultisimWithCompatibility -Report $report -AllowCandidateBuild:$AllowCandidateBuild -ConfirmDatabaseError:$ConfirmDatabaseError
        if ($Json) { $result | ConvertTo-Json } else { $result | Format-List }
    }
    'InstallShortcut' {
        $entry = Join-Path $repositoryRoot 'Multisim兼容启动.cmd'
        $path = New-MultisimCompatibleShortcut -EntryScript $entry -Report $report -Name $ShortcutName -Force:$Force
        if ($Json) { [pscustomobject]@{ Path = $path } | ConvertTo-Json } else { Write-Host "已创建快捷方式：$path" }
    }
    default {
        throw "未知动作：$Action"
    }
}
