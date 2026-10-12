# SPDX-FileCopyrightText: 2026 multisimcompatfix contributors
# SPDX-License-Identifier: MIT

function Initialize-WindowsPowerShellModulePath {
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSEdition -ne 'Desktop') {
        return
    }

    $modulePaths = [Collections.Generic.List[string]]::new()
    $inboxModulePath = Join-Path $PSHOME 'Modules'
    $modulePaths.Add($inboxModulePath)

    foreach ($candidate in @([Environment]::GetEnvironmentVariable('PSModulePath', 'Machine') -split ';')) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        if ($candidate -notmatch '(?i)\\WindowsPowerShell\\(?:v1\.0\\)?Modules$') {
            continue
        }
        if (@($modulePaths | Where-Object { $_.Equals($candidate, [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
            $modulePaths.Add($candidate)
        }
    }

    $env:PSModulePath = $modulePaths -join ';'

    foreach ($moduleName in @('Microsoft.PowerShell.Security', 'Microsoft.PowerShell.Utility')) {
        $manifestPath = Join-Path $inboxModulePath "$moduleName\$moduleName.psd1"
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw "Windows PowerShell inbox module was not found: $manifestPath"
        }
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
    }
}
