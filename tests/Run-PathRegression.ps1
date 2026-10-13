# SPDX-License-Identifier: MIT
# Windows-only behavioural regressions. No Multisim or Locale Emulator download is required.
# Fake executable files are hashed in /check mode only, never executed.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT') { throw 'Run this suite on Windows.' }
if (@(Get-Process -Name multisim -ErrorAction SilentlyContinue).Count) { throw 'Close Multisim before running the suite.' }
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$utf8 = [Text.UTF8Encoding]::new($false)
$gbk = [Text.Encoding]::GetEncoding(936)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('mscompat-regression-' + [guid]::NewGuid().ToString('N'))
$script:passed = 0
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAILED: $Message" }
    $script:passed++
    Write-Host "PASS: $Message"
}
function Write-Text([string]$Path, [string]$Text) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}
function Write-Cmd([string]$Path, [string]$Text) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllBytes($Path, $gbk.GetBytes(($Text -replace "`r`n", "`n" -replace "`n", "`r`n")))
}
function Invoke-Cmd([string]$Path, [string]$Arguments = '') {
    # No generated wrapper: literal percent signs must not be written unescaped into batch source.
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $env:ComSpec
    $psi.Arguments = '/d /v:on /c ""!MSCOMPAT_TEST_SCRIPT!" ' + $Arguments + '"'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $tmp
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $gbk
    $psi.StandardErrorEncoding = $gbk
    $psi.EnvironmentVariables['MSCOMPAT_TEST_SCRIPT'] = $Path
    $psi.EnvironmentVariables['MSCOMPAT_PERCENT_TEST'] = 'EXPANDED_WRONGLY'
    $psi.EnvironmentVariables['MSCOMPAT_NOPAUSE'] = '1'
    $psi.EnvironmentVariables['MSCOMPAT_CHECK_NOPAUSE'] = '1'
    # Deterministic GBK code page, without interpolating a path into a command string.
    $psi.Arguments = '/d /v:on /c "chcp 936 >nul & "!MSCOMPAT_TEST_SCRIPT!" ' + $Arguments + '"'
    $p = [Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEndAsync()
    $stderr = $p.StandardError.ReadToEndAsync()
    try {
        if (-not $p.WaitForExit(30000)) { $p.Kill(); throw 'CMD regression timed out.' }
        [pscustomobject]@{ Code = $p.ExitCode; Text = $stdout.Result + $stderr.Result }
    } finally { $p.Dispose() }
}
function Copy-Commands([string]$Dir) {
    foreach ($pair in @(@('launch', 'Multisim兼容启动.cmd'), @('check', 'Multisim兼容检查.cmd'), @('uninstall', '卸载.cmd'))) {
        Write-Cmd (Join-Path $Dir $pair[1]) ([IO.File]::ReadAllText((Join-Path $root ('src\cmd\' + $pair[0] + '.cmd.utf8')), $utf8))
    }
}
try {
    [void][IO.Directory]::CreateDirectory($tmp)
    $fixture = Join-Path $tmp '张三 & (x86) %MSCOMPAT_PERCENT_TEST% !literal!'
    Copy-Commands $fixture
    $ni = Join-Path $fixture 'fake-ni'
    $hashes = @()
    foreach ($name in 'multisim.exe', 'LibraryAccess.dll', 'WidgetLibrary.dll') {
        $p = Join-Path $ni $name
        Write-Text $p ('Not executable: ' + $name)
        $hashes += (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
    }
    $fakeRuntime = Join-Path $fixture 'runtime\locale-emulator\LEProc.exe'
    Write-Text $fakeRuntime 'Not executable: fixture runtime'
    $rtHash = (Get-FileHash -LiteralPath $fakeRuntime -Algorithm SHA256).Hash
    Write-Text (Join-Path $fixture 'config\cmd-gate.txt') ("B,$($hashes -join ','),fixture`r`nR,$rtHash,LEProc.exe`r`n")
    [IO.File]::WriteAllText((Join-Path $fixture 'config\multisim-path.txt'), (Join-Path $ni 'multisim.exe'), $gbk)
    Write-Text (Join-Path $fixture 'config\install.txt') 'VERSION=fixture'
    $entry = Join-Path $fixture 'Multisim兼容启动.cmd'
    $check = Join-Path $fixture 'Multisim兼容检查.cmd'
    $result = Invoke-Cmd $entry '/check'
    Assert ($result.Code -eq 0) ('Check succeeds with literal percent, bang, ampersand, parentheses and Chinese paths: ' + $result.Text)
    $log = [IO.File]::ReadAllText((Join-Path $fixture 'logs\launch.log'), $gbk)
    Assert ($log.Contains((Join-Path $ni 'multisim.exe'))) 'Log preserves the complete literal target path'
    Assert (-not $log.Contains('EXPANDED_WRONGLY')) 'Percent variable names in paths are not expanded again'
    $result = Invoke-Cmd $check
    Assert ($result.Code -eq 0) ('Check wrapper propagates success: ' + $result.Text)
    $report = [IO.File]::ReadAllText((Join-Path $fixture 'logs\check-latest.txt'), $gbk)
    Assert ($report.Contains('启动器检查退出码：0')) 'Report records the successful child exit code'
    Write-Text $fakeRuntime 'changed runtime'
    $result = Invoke-Cmd $check
    Assert ($result.Code -eq 1) ('Check wrapper propagates runtime hash failure: ' + $result.Text)
    $report = [IO.File]::ReadAllText((Join-Path $fixture 'logs\check-latest.txt'), $gbk)
    Assert ($report.Contains('启动器检查退出码：1')) 'Report records the failed child exit code'

    # An ordinary directory with an uninstaller must survive, without hanging at PAUSE.
    $notOurs = Join-Path $tmp 'not-ours %MSCOMPAT_PERCENT_TEST%'
    Copy-Commands $notOurs
    Write-Text (Join-Path $notOurs 'keep.txt') 'keep'
    $result = Invoke-Cmd (Join-Path $notOurs '卸载.cmd') '/y'
    Assert ($result.Code -ne 0 -and (Test-Path -LiteralPath (Join-Path $notOurs 'keep.txt'))) 'Uninstaller rejects unrelated directories non-interactively'
    $result = Invoke-Cmd (Join-Path $fixture '卸载.cmd') '/y'
    for ($i = 0; $i -lt 40 -and (Test-Path -LiteralPath $fixture); $i++) { Start-Sleep -Milliseconds 250 }
    Assert (-not (Test-Path -LiteralPath $fixture)) ('Uninstaller removes its percent/bang path: ' + $result.Text)
    Assert (Test-Path -LiteralPath (Join-Path $notOurs 'keep.txt')) 'Uninstall preserves neighbouring files'

    # Small synthetic ZIP exercises the real installer without executing any bundled binaries.
    $payload = Join-Path $tmp 'payload\MultisimCompat'
    Copy-Commands $payload
    $runtime = Join-Path $payload 'runtime\locale-emulator\LEProc.exe'
    Write-Text $runtime 'Not executable: fixture runtime'
    $runtimeHash = (Get-FileHash -LiteralPath $runtime -Algorithm SHA256).Hash
    Write-Text (Join-Path $payload 'config\cmd-gate.txt') "R,$runtimeHash,LEProc.exe`r`n"
    $zip = Join-Path $tmp 'fixture.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory((Split-Path -Parent $payload), $zip)
    $zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    $installer = [scriptblock]::Create([IO.File]::ReadAllText((Join-Path $root 'install.ps1'), $utf8))
    $dest = Join-Path $tmp 'install %MSCOMPAT_PERCENT_TEST% !literal! & (x86)'
    foreach ($suffix in '.new', '.old', '.flat') { Write-Text (Join-Path ($dest + $suffix) 'keep.txt') $suffix }
    & $installer -InstallDir $dest -ZipPath $zip -ExpectedSha256 $zipHash -NoShortcut -Yes
    Assert (Test-Path -LiteralPath (Join-Path $dest 'config\install.txt')) 'Installer accepts the synthetic verified ZIP'
    foreach ($suffix in '.new', '.old', '.flat') {
        Assert (([IO.File]::ReadAllText((Join-Path ($dest + $suffix) 'keep.txt'))) -eq $suffix) ("Install preserves unrelated $suffix directory")
    }
    Write-Text (Join-Path $dest 'logs\keep.log') 'persist'
    & $installer -Action Update -InstallDir $dest -ZipPath $zip -ExpectedSha256 $zipHash -NoShortcut -Yes
    Assert (([IO.File]::ReadAllText((Join-Path $dest 'logs\keep.log'))) -eq 'persist') 'Update preserves existing logs'
    foreach ($suffix in '.new', '.old', '.flat') {
        Assert (([IO.File]::ReadAllText((Join-Path ($dest + $suffix) 'keep.txt'))) -eq $suffix) ("Update preserves unrelated $suffix directory")
    }
    Assert (@(Get-ChildItem -LiteralPath $tmp -Directory -Filter 'mscompat-transaction-*').Count -eq 0) 'Successful installation cleans only its own transaction directory'
    $rejected = Join-Path $tmp 'rejected'
    & $installer -InstallDir $rejected -ZipPath $zip -ExpectedSha256 ('0' * 64) -NoShortcut -Yes
    Assert (-not (Test-Path -LiteralPath $rejected)) 'Wrong ZIP hash creates no installation'
    Assert (@(Get-ChildItem -LiteralPath $tmp -Directory -Filter 'mscompat-transaction-*').Count -eq 0) 'Rejected ZIP leaves no transaction directory'
    Write-Host "Passed: $script:passed"
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
}
