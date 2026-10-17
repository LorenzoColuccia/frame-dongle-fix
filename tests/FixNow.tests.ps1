. (Join-Path $PSScriptRoot 'Helpers.ps1')
$ctx = Initialize-Test 'fix'
. ([scriptblock]::Create((Get-Payload $ctx.Cmd)))

function Get-Date { param([Parameter(ValueFromRemainingArguments)]$a) return $global:Fake }
function Start-Sleep { param($Seconds) $global:Fake = $global:Fake.AddSeconds($Seconds) }
function Is-Healed { return [bool]($global:Restarted -and $global:Heal -and (($global:Fake - $global:Restarted).TotalSeconds -ge 10)) }
function Is-Up { return ($global:AlreadyUp -or (Is-Healed)) }
function Get-NetAdapter { param([Parameter(ValueFromRemainingArguments)]$a)
    if ($global:Absent) { return $null }
    return [pscustomobject]@{ Name = 'Wi-Fi 6'; InterfaceDescription = 'Realtek 8832CU Wireless LAN WiFi 6 USB NIC For Valve'; Status = $(if (Is-Up) { 'Up' } else { 'Disconnected' }) }
}
function Get-NetIPAddress { param([Parameter(ValueFromRemainingArguments)]$a)
    if (Is-Up) { return [pscustomobject]@{ IPAddress = '10.35.78.23' } }
    return [pscustomobject]@{ IPAddress = '169.254.1.2' }
}
function Restart-NetAdapter { param([Parameter(ValueFromRemainingArguments)]$a) $global:RestartCalls++; $global:Restarted = $global:Fake }
function Get-WinEvent { param([Parameter(ValueFromRemainingArguments)]$a)
    $message = 'WLAN AutoConfig service failed to connect. Interface GUID: {314a8ba5-84e7-4c7d-a970-a6391163a5c9} Profile Name: frame_C050229D_3 SSID: frame_C050229D Failure Reason: The specific network is not available. RSSI: 255'
    return @([pscustomobject]@{ Message = $message }, [pscustomobject]@{ Message = $message })
}
function Test-Connection { param([Parameter(ValueFromRemainingArguments)]$a) return $true }
function Get-ScheduledTask { param([Parameter(ValueFromRemainingArguments)]$a) return $null }
function Test-Admin { return $true }

function Scenario([hashtable]$o, [string]$mode = 'fix') {
    $global:Fake = [datetime]'2026-10-17 13:00:00'
    $global:Restarted = $null
    $global:RestartCalls = 0
    $global:Heal = [bool]$o.Heal
    $global:AlreadyUp = [bool]$o.AlreadyUp
    $global:Absent = [bool]$o.Absent
    $reportFile = Join-Path $ctx.Root 'Frame-Dongle-Fix-report.txt'
    if (Test-Path $reportFile) { Remove-Item $reportFile }
    $code = @(Invoke-Mode $mode)[-1]
    $text = if (Test-Path $reportFile) { Get-Content $reportFile -Raw } else { '' }
    return @{ Code = $code; Calls = $global:RestartCalls; Report = $text }
}

$r = Scenario @{ Heal = $true }
Check ($r.Code -eq 0 -and $r.Calls -eq 1) 'a blind dongle is restarted once and the run reports success'
Check ($r.Report -match 'CONNECTED' -and $r.Report -match 'Ping to the Frame: answers') 'the report says it connected and the ping answered'
Check ($r.Report -match '2 x Failure Reason: The specific network is not available') 'the report groups the Wi-Fi failure reasons from the event log'
Check ($r.Report -notmatch 'C050229D' -and $r.Report -notmatch '314a8ba5') 'the report does not contain the hotspot name or the interface GUID'

$r = Scenario @{ AlreadyUp = $true }
Check ($r.Code -eq 0 -and $r.Calls -eq 0 -and $r.Report -match 'ALREADY connected') 'an already connected dongle is not restarted'

$r = Scenario @{ Heal = $false }
Check ($r.Code -eq 3 -and $r.Calls -eq 1 -and $r.Report -match 'NOT connected') 'a restart that does not help is reported honestly'

$r = Scenario @{ Absent = $true }
Check ($r.Code -eq 1 -and $r.Calls -eq 0 -and $r.Report -match 'plugged in') 'no dongle: it says so and restarts nothing'

$r = Scenario @{ AlreadyUp = $true } 'status'
Check ($r.Code -eq 0 -and $r.Report -match 'linked to the Frame: yes' -and $r.Report -match 'Auto-fix: not installed') 'status reports the link and the auto-fix state'

function Read-Host { param([Parameter(ValueFromRemainingArguments)]$a) return '1' }
$r = Scenario @{ Heal = $true } ''
Check ($r.Code -eq 0 -and $r.Calls -eq 1) 'choosing 1 in the menu runs the fix'

Remove-Item $ctx.Root -Recurse -Force
Finish
