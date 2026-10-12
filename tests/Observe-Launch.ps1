# 启动一个测试用 Multisim 进程，按 PID 轮询其可见窗口，记录事件并截图。
# 只观察本脚本启动的新 PID；不会结束、也不会操作任何已有 Multisim 进程。
# -DismissErrors：自动点掉测试进程里的数据库错误弹窗（按“确定/OK”）。
param(
    [ValidateSet('Normal', 'Compat')][string]$Mode = 'Normal',
    [int]$Seconds = 120,
    [switch]$DismissErrors,
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)
$ErrorActionPreference = 'Stop'
$exe = 'C:\Program Files (x86)\National Instruments\Circuit Design Suite 14.0\multisim.exe'
$spy = Join-Path $Root 'build\WinSpy.exe'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dir = Join-Path $Root "logs\$Mode-$stamp"
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$events = Join-Path $dir 'events.txt'
function Log([string]$m) { $l = "$((Get-Date).ToString('HH:mm:ss')) $m"; Add-Content -LiteralPath $events -Value $l -Encoding UTF8; Write-Output $l }

$before = @(Get-Process multisim -ErrorAction SilentlyContinue | ForEach-Object Id)
$commonX86 = ${env:CommonProgramFiles(x86)}
$psi = [Diagnostics.ProcessStartInfo]::new()
$psi.UseShellExecute = $false
$psi.EnvironmentVariables['CommonProgramFiles'] = $commonX86
if ($Mode -eq 'Normal') {
    $psi.FileName = $exe
    $psi.WorkingDirectory = Split-Path $exe
} else {
    $le = Join-Path $Root 'runtime\locale-emulator\LEProc.exe'
    $psi.FileName = $le
    $psi.Arguments = '-runas ffb361ae-febe-4cdb-aff4-0294d2623d1a "' + $exe + '"'
    $psi.WorkingDirectory = Split-Path $le
}
$p = [Diagnostics.Process]::Start($psi)
$msPid = $null
for ($i = 0; $i -lt 60 -and -not $msPid; $i++) {
    Start-Sleep -Milliseconds 500
    $msPid = @(Get-Process multisim -ErrorAction SilentlyContinue | Where-Object { $_.Id -notin $before } | ForEach-Object Id) | Select-Object -First 1
}
if (-not $msPid) { Log "FAIL: launcher pid $($p.Id) produced no new multisim process"; exit 2 }
Log "mode=$Mode launcherPid=$($p.Id) multisimPid=$msPid preexisting=[$($before -join ',')]"

$seen = @{}
$deadline = (Get-Date).AddSeconds($Seconds)
$mainSeenAt = $null
while ((Get-Date) -lt $deadline) {
    if (-not (Get-Process -Id $msPid -ErrorAction SilentlyContinue)) { Log 'multisim process exited'; break }
    $lines = @(& $spy list $msPid)
    ($lines -join "`n") | Set-Content -LiteralPath (Join-Path $dir 'last-windows.jsonl') -Encoding UTF8
    $cur = $null
    foreach ($l in $lines) {
        if ($l -match '^\{"hwnd":(\d+),"class":"((?:[^"\\]|\\.)*)","title":"((?:[^"\\]|\\.)*)"') {
            $cur = @{ H = $Matches[1]; Cls = $Matches[2]; Title = $Matches[3]; Text = @() }
            if (-not $seen.ContainsKey($cur.H)) {
                $seen[$cur.H] = $cur
                $cur.New = $true
            } else { $cur.New = $false }
        } elseif ($cur -and $l -match '"class":"Static","text":"((?:[^"\\]|\\.)+)"') {
            $cur.Text += $Matches[1]
        } elseif ($l -eq ']}' -and $cur) {
            if ($cur.New) {
                Start-Sleep -Milliseconds 500
                $png = Join-Path $dir ("win{0:D2}-{1}.png" -f $seen.Count, $cur.H)
                & $spy shot $cur.H $png | Out-Null
                Log ("NEW hwnd={0} class={1} title=[{2}] text=[{3}]" -f $cur.H, $cur.Cls, $cur.Title, ($cur.Text -join ' | '))
                if ($cur.Cls -ne '#32770' -and $cur.Title -match 'Multisim' -and -not $mainSeenAt) { $mainSeenAt = Get-Date; Log "MAIN window candidate hwnd=$($cur.H)" }
            }
            if ($DismissErrors -and $cur.Cls -eq '#32770' -and (($cur.Text -join ' ') -match 'cannot be accessed|database|Database|数据库')) {
                $r = & $spy click $cur.H 'OK'
                if ($LASTEXITCODE -ne 0) { $r = & $spy click $cur.H '确定' }
                Log "DISMISS hwnd=$($cur.H): $r"
            }
            $cur = $null
        }
    }
    if ($mainSeenAt -and ((Get-Date) - $mainSeenAt).TotalSeconds -gt 25) { break }
    Start-Sleep -Milliseconds 800
}
Log "observation end; multisimPid=$msPid alive=$([bool](Get-Process -Id $msPid -ErrorAction SilentlyContinue))"
Set-Content -LiteralPath (Join-Path $dir 'pid.txt') -Value $msPid
Write-Output "dir=$dir"
