. (Join-Path $PSScriptRoot 'Helpers.ps1')
$ctx = Initialize-Test 'decide'
. ([scriptblock]::Create((Get-Payload $ctx.Cmd)))

$t0 = [datetime]'2026-10-17 13:00:00'

function Obs([hashtable]$over) {
    $o = @{ Present = $true; Connected = $false; Status = 'Disconnected'; Name = 'Wi-Fi 2'; SteamSince = $t0.AddHours(-3) }
    foreach ($k in $over.Keys) { $o[$k] = $over[$k] }
    return $o
}

function Run($s, $o, [int]$fromSec, [int]$toSec, [int]$step = 4) {
    $restarts = @()
    $logs = @()
    for ($t = $fromSec; $t -le $toSec; $t += $step) {
        $r = Decide $s $o $t0.AddSeconds($t)
        if ($r.Action -eq 'restart') { $restarts += $t }
        $logs += $r.Logs
    }
    return @{ Restarts = $restarts; Logs = $logs }
}

$s = New-State
$r = Run $s (Obs @{}) 0 28
Check ($r.Restarts.Count -eq 0) 'no restart during the first 28 s of disconnection'
$r = Run $s (Obs @{}) 32 40
Check ($r.Restarts.Count -eq 1 -and $r.Restarts[0] -ge 32 -and $r.Restarts[0] -le 36) 'first restart after about 30 s'
$first = $r.Restarts[0]
$r = Run $s (Obs @{}) 44 140
Check ($r.Restarts.Count -eq 1) 'second restart after the 60 s delay'
$second = $r.Restarts[0]
Check (($second - $first) -ge 60 -and ($second - $first) -le 64) 'first and second restart are 60 s apart'
$r = Run $s (Obs @{}) ($second + 4) ($second + 200)
Check ($r.Restarts.Count -eq 1 -and ($r.Restarts[0] - $second) -ge 120 -and ($r.Restarts[0] - $second) -le 124) 'third restart after 120 s (doubling)'

$s = New-State
$null = Run $s (Obs @{}) 0 36
$r = Run $s (Obs @{ Connected = $true; Status = 'Up' }) 40 44
Check (($r.Logs -join '|') -match 'connected \d+ s after the restart') 'the connection after a restart is logged'
$r = Run $s (Obs @{}) 48 80
Check ($r.Restarts.Count -eq 1) 'after a connection the waiting starts over'
Check ($s.Backoff -eq 120) 'after a connection the delay is back to 60 s before the next restart'

$s = New-State
$null = Run $s (Obs @{}) 0 20
$r = Run $s (Obs @{ Connected = $true; Status = 'Up' }) 24 28
Check (($r.Logs -join '|') -match 'connected by itself') 'it connected by itself'
Check ($r.Restarts.Count -eq 0) 'no restart when it connects by itself'

$s = New-State
$r = Run $s (Obs @{ SteamSince = $null }) 0 400
Check ($r.Restarts.Count -eq 0) 'Steam closed: no restart'
$s = New-State
$r = Run $s (Obs @{ SteamSince = $t0.AddSeconds(30) }) 0 36
Check ($r.Restarts.Count -eq 0) 'Steam just started (under 40 s): no restart'
$r = Run $s (Obs @{ SteamSince = $t0.AddSeconds(30) }) 40 80
Check ($r.Restarts.Count -ge 1) 'Steam running for 40 s: restart allowed'

foreach ($status in @('Disabled', 'Not Present', 'Up')) {
    $s = New-State
    $r = Run $s (Obs @{ Status = $status }) 0 300
    Check ($r.Restarts.Count -eq 0) "status $status : no restart"
}

$s = New-State
$null = Run $s (Obs @{}) 0 36
$r = Run $s (Obs @{}) 700 740
Check (($r.Logs -join '|') -match 'resume from sleep') 'an 11 minute gap is recognised as a resume'
Check ($r.Restarts.Count -eq 1 -and $r.Restarts[0] -ge 730) 'after a resume it waits the 30 s again'

$s = New-State
$null = Run $s (Obs @{}) 0 36
$r = Run $s (Obs @{ Present = $false }) 40 60
Check (($r.Logs -join '|') -match 'dongle removed') 'removal is logged'
$r = Run $s (Obs @{}) 64 100
Check (($r.Logs -join '|') -match 'plugged in') 'plugging in again is logged'
Check ($r.Restarts.Count -eq 1 -and $r.Restarts[0] -ge 94) 'after plugging in it restarts after about 30 s of disconnection'

$s = New-State
$all = @()
$t = 0
for ($i = 0; $i -lt 3000; $i++) {
    $r = Decide $s (Obs @{}) $t0.AddSeconds($t)
    if ($r.Action -eq 'restart') { $all += $t }
    $t += 4
}
$hour = @($all | Where-Object { $_ -lt 3600 })
Check ($hour.Count -le 8) ("at most 8 restarts in the first hour (saw {0})" -f $hour.Count)
Check ($s.Backoff -le 600) 'the delay never exceeds 10 minutes'

Remove-Item $ctx.Root -Recurse -Force
Finish
