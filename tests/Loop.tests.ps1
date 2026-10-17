. (Join-Path $PSScriptRoot 'Helpers.ps1')
$ctx = Initialize-Test 'loop'
. ([scriptblock]::Create((Get-Payload $ctx.Cmd)))

function Get-Date { param([Parameter(ValueFromRemainingArguments)]$a) return $global:Fake }
function Start-Sleep { param([int]$Seconds)
    $global:Ticks++
    $global:Fake = $global:Fake.AddSeconds($Seconds + 1)
    if ($global:Ticks -ge $global:Limit) { throw 'STOP' }
}
function Is-Healed { return [bool]($global:Restarted -and $global:Heal) }
function Get-NetAdapter { param([Parameter(ValueFromRemainingArguments)]$a)
    if (-not $global:Present) { return $null }
    $status = if (Is-Healed) { 'Up' } else { 'Disconnected' }
    return [pscustomobject]@{ Name = 'Wi-Fi 6'; InterfaceDescription = 'Realtek 8832CU Wireless LAN WiFi 6 USB NIC For Valve'; Status = $status }
}
function Get-NetIPAddress { param([Parameter(ValueFromRemainingArguments)]$a)
    if (Is-Healed) { return [pscustomobject]@{ IPAddress = '10.35.78.23' } }
    return [pscustomobject]@{ IPAddress = '169.254.10.20' }
}
function Get-Process { param([Parameter(ValueFromRemainingArguments)]$a)
    if (-not $global:SteamOn) { return $null }
    return [pscustomobject]@{ StartTime = $global:Fake.AddHours(-3) }
}
function Restart-NetAdapter { param([Parameter(ValueFromRemainingArguments)]$a)
    $global:RestartCalls++
    $global:Restarted = $global:Fake
}
function Get-NetAdapterAdvancedProperty { param([Parameter(ValueFromRemainingArguments)]$a)
    return @(
        [pscustomobject]@{ DisplayName = '2.4G Wireless Mode'; DisplayValue = '802.11 b/g' },
        [pscustomobject]@{ DisplayName = '5G Wireless Mode'; DisplayValue = '802.11 a/n' }
    )
}

function Scenario([hashtable]$o) {
    $global:Fake = [datetime]'2026-10-17 13:00:00'
    $global:Ticks = 0
    $global:Limit = $o.Ticks
    $global:Restarted = $null
    $global:RestartCalls = 0
    $global:Heal = [bool]$o.Heal
    $global:Present = -not $o.Absent
    $global:SteamOn = -not $o.NoSteam
    $script:LogFile = Join-Path $ctx.Root ('log-{0}.txt' -f [guid]::NewGuid().ToString('N'))
    try { Invoke-Mode 'watch' | Out-Null } catch { if ($_.Exception.Message -ne 'STOP') { throw } }
    $text = if (Test-Path $script:LogFile) { Get-Content $script:LogFile -Raw } else { '' }
    return @{ Calls = $global:RestartCalls; Log = $text }
}

$r = Scenario @{ Heal = $true; Ticks = 20 }
Check ($r.Calls -eq 1) 'a blind dongle is restarted once'
Check ($r.Log -match 'restarting adapter Wi-Fi 6\. Settings: 2\.4G Wireless Mode=802\.11 b/g; 5G Wireless Mode=802\.11 a/n') 'the log records the adapter settings at the moment of the restart'
Check ($r.Log -match 'connected \d+ s after the restart') 'the log records that the restart worked'

$r = Scenario @{ Heal = $false; Ticks = 60 }
Check ($r.Calls -eq 3) 'when the restart does not help it retries with growing delays'
Check ($r.Log -notmatch 'connected') 'no connection is claimed when there is none'

$r = Scenario @{ Heal = $true; Ticks = 20; NoSteam = $true }
Check ($r.Calls -eq 0) 'Steam not running: the adapter is left alone'

$r = Scenario @{ Heal = $true; Ticks = 20; Absent = $true }
Check ($r.Calls -eq 0) 'no dongle: nothing to restart'

Remove-Item $ctx.Root -Recurse -Force
Finish
