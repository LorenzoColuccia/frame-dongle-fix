@echo off
setlocal EnableExtensions
set "FDF_SELF=%~f0"
set "FDF_MODE=%~1"
set "FDF_PATTERN=%~2"
if /i "%FDF_MODE%"=="watch" goto run
fltmc >nul 2>&1 && goto run
if /i "%FDF_MODE%"=="elevated" goto noadmin
powershell -NoProfile -Command "Start-Process -FilePath $env:FDF_SELF -ArgumentList 'elevated' -Verb RunAs"
exit /b
:noadmin
echo Administrator permission is needed: right-click this file and choose Run as administrator.
pause
exit /b 1
:run
if /i "%FDF_MODE%"=="elevated" set "FDF_MODE="
title Frame Dongle Fix
powershell -NoProfile -Command "$t = [IO.File]::ReadAllText($env:FDF_SELF); Invoke-Expression $t.Substring($t.IndexOf('#PAY'+'LOAD#'))"
set "FDF_CODE=%errorlevel%"
if not defined FDF_MODE pause
exit /b %FDF_CODE%
#PAYLOAD#
$ErrorActionPreference = 'Continue'
$Self = $env:FDF_SELF
$Mode = $env:FDF_MODE
$Pattern = if ($env:FDF_PATTERN) { $env:FDF_PATTERN } else { '8832CU|Valve' }
$TaskName = 'Frame Dongle Fix'
$Dir = Join-Path $env:ProgramData 'FrameDongleFix'
$Installed = Join-Path $Dir 'Frame-Dongle-Fix.cmd'
$LogFile = Join-Path $Dir 'log.txt'
$LinkPrefix = '10.35.78.'
$FrameAddress = '10.35.78.1'
$Settle = 30
$SteamSettle = 40
$ResumeGap = 30
$MaxPerHour = 8
$MaxBackoff = 600
$StartBackoff = 60
$Report = $null

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-Dongle([string]$Match) {
    return Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match $Match } | Select-Object -First 1
}

function Test-Linked([string]$Name) {
    $adapter = Get-NetAdapter -Name $Name -ErrorAction SilentlyContinue
    $address = Get-NetIPAddress -InterfaceAlias $Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like ($LinkPrefix + '*') }
    return [bool]($adapter -and $adapter.Status -eq 'Up' -and $address)
}

function Hide-Private([string]$Text) {
    $clean = $Text -replace '\{[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\}', '{GUID}'
    $clean = $clean -replace '([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}', 'xx:xx:xx:xx:xx:xx'
    return $clean -replace 'frame_[0-9a-fA-F]+', 'frame_XXXXXXXX'
}

function Open-Report {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $label = if ($Mode) { $Mode } else { 'menu' }
    foreach ($folder in @((Split-Path -Parent $Self), $env:TEMP)) {
        if (-not $folder) { continue }
        try {
            $path = Join-Path $folder 'Frame-Dongle-Fix-report.txt'
            [System.IO.File]::AppendAllText($path, ("--- {0:yyyy-MM-dd HH:mm:ss} {1}`r`n" -f (Get-Date), $label), $utf8)
            return $path
        } catch {}
    }
    return $null
}

function Say([string]$text) {
    $line = '{0:HH:mm:ss} {1}' -f (Get-Date), $text
    Write-Host $line
    if ($Report) {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::AppendAllText($Report, (Hide-Private $line) + "`r`n", $utf8)
    }
}

function Log([string]$text) {
    try {
        if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt 200KB)) {
            Move-Item -Path $LogFile -Destination (Join-Path $Dir 'log.old.txt') -Force
        }
        Add-Content -Path $LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $text) -Encoding UTF8
    } catch {}
}

function New-State {
    return @{
        Present = $false
        DisconnectedSince = $null
        NextAllowed = [datetime]::MinValue
        Backoff = $StartBackoff
        Restarts = @()
        LastRestart = $null
        LastTick = $null
        CapLogged = $false
    }
}

function Reset-Wait($s) {
    $s.DisconnectedSince = $null
    $s.Backoff = $StartBackoff
    $s.NextAllowed = [datetime]::MinValue
}

function Decide($s, $o, [datetime]$now) {
    $r = @{ Action = 'none'; Logs = New-Object System.Collections.ArrayList }
    if ($s.LastTick -and (($now - $s.LastTick).TotalSeconds -gt $ResumeGap)) {
        [void]$r.Logs.Add('long pause or resume from sleep: starting over')
        Reset-Wait $s
    }
    $s.LastTick = $now
    if (-not $o.Present) {
        if ($s.Present) { [void]$r.Logs.Add('dongle removed') }
        $s.Present = $false
        $s.DisconnectedSince = $null
        return $r
    }
    if (-not $s.Present) {
        $s.Present = $true
        Reset-Wait $s
        [void]$r.Logs.Add('dongle plugged in or found')
    }
    if ($o.Connected) {
        if ($s.LastRestart) {
            [void]$r.Logs.Add(('connected {0:N0} s after the restart' -f ($now - $s.LastRestart).TotalSeconds))
            $s.LastRestart = $null
        } elseif ($s.DisconnectedSince) {
            [void]$r.Logs.Add('connected by itself')
        }
        Reset-Wait $s
        return $r
    }
    if ($o.Status -ne 'Disconnected') { return $r }
    if (-not $s.DisconnectedSince) { $s.DisconnectedSince = $now }
    if (($now - $s.DisconnectedSince).TotalSeconds -lt $Settle) { return $r }
    if (-not $o.SteamSince -or (($now - $o.SteamSince).TotalSeconds -lt $SteamSettle)) { return $r }
    if ($now -lt $s.NextAllowed) { return $r }
    $recent = @($s.Restarts | Where-Object { ($now - $_).TotalMinutes -lt 60 })
    $s.Restarts = $recent
    if ($recent.Count -ge $MaxPerHour) {
        if (-not $s.CapLogged) {
            [void]$r.Logs.Add(('limit of {0} restarts per hour reached: waiting' -f $MaxPerHour))
            $s.CapLogged = $true
        }
        return $r
    }
    $s.CapLogged = $false
    $s.Restarts = @($recent) + @($now)
    $s.LastRestart = $now
    $s.NextAllowed = $now.AddSeconds($s.Backoff)
    $s.Backoff = [Math]::Min($s.Backoff * 2, $MaxBackoff)
    $r.Action = 'restart'
    return $r
}

function Observe {
    $adapter = Find-Dongle $Pattern
    $o = @{ Present = [bool]$adapter; Connected = $false; Status = ''; Name = ''; SteamSince = $null }
    if ($adapter) {
        $o.Name = $adapter.Name
        $o.Status = [string]$adapter.Status
        $o.Connected = Test-Linked $adapter.Name
    }
    $steam = Get-Process -Name steam -ErrorAction SilentlyContinue | Sort-Object StartTime | Select-Object -First 1
    if ($steam) { $o.SteamSince = $steam.StartTime }
    return $o
}

function Describe-Settings([string]$name) {
    try {
        return ((Get-NetAdapterAdvancedProperty -Name $name -ErrorAction Stop | ForEach-Object { '{0}={1}' -f $_.DisplayName, $_.DisplayValue }) -join '; ')
    } catch { return 'not readable' }
}

function Invoke-Watch {
    $mutex = New-Object System.Threading.Mutex($false, 'Global\FrameDongleFixWatcher')
    if (-not $mutex.WaitOne(0)) { return }
    Log ('started, looking for an adapter matching "{0}"' -f $Pattern)
    $s = New-State
    while ($true) {
        try {
            $o = Observe
            $r = Decide $s $o (Get-Date)
            foreach ($m in $r.Logs) { Log $m }
            if ($r.Action -eq 'restart') {
                Log ('restarting adapter {0}. Settings: {1}' -f $o.Name, (Describe-Settings $o.Name))
                try {
                    Restart-NetAdapter -Name $o.Name -Confirm:$false -ErrorAction Stop
                    Log 'adapter restarted'
                } catch {
                    Log ('restart FAILED: ' + $_.Exception.Message)
                }
            }
        } catch {
            Log ('error: ' + $_.Exception.Message)
        }
        Start-Sleep -Seconds 4
    }
}

function Show-Failures([datetime]$from, [string]$title) {
    Say $title
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-WLAN-AutoConfig/Operational'; Id = 8002; StartTime = $from } -ErrorAction Stop | Where-Object { $_.Message -match 'frame_' })
        Say ('  failed attempts towards the Frame hotspot: {0}' -f $events.Count)
        $reasons = $events | Group-Object { if (($_.Message -replace '\s+', ' ') -match 'Failure Reason:.{0,160}') { $matches[0] } else { 'no reason given' } }
        foreach ($g in $reasons) { Say ('  {0} x {1}' -f $g.Count, $g.Name) }
    } catch {
        Say '  no data available'
    }
}

function Wait-Linked([string]$name, [int]$seconds) {
    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $seconds) {
        Start-Sleep -Seconds 1
        if (Test-Linked $name) { return ((Get-Date) - $start).TotalSeconds }
    }
    return $null
}

function Invoke-Fix {
    $dongle = Find-Dongle $Pattern
    if (-not $dongle) {
        Say ('No adapter matching "{0}" was found. Is the dongle plugged in?' -f $Pattern)
        return 1
    }
    $name = $dongle.Name
    Say ('Adapter: {0} ({1}), status: {2}' -f $name, $dongle.InterfaceDescription, $dongle.Status)
    if (Test-Linked $name) {
        Say 'The dongle is ALREADY connected to the Frame (address 10.35.78.x): nothing to do.'
        return 0
    }
    Show-Failures (Get-Date).AddMinutes(-10) 'Before the restart (last 10 minutes):'
    Say 'Restarting the adapter, like changing a value in Device Manager, without changing any setting...'
    try {
        Restart-NetAdapter -Name $name -Confirm:$false -ErrorAction Stop
    } catch {
        Say ('The restart FAILED: ' + $_.Exception.Message)
        return 2
    }
    $seconds = Wait-Linked $name 45
    if ($null -ne $seconds) {
        Say ('CONNECTED: the dongle linked up with the Frame {0:N0} seconds after the restart.' -f $seconds)
        $reply = Test-Connection -ComputerName $FrameAddress -Count 2 -Quiet -ErrorAction SilentlyContinue
        Say ('Ping to the Frame: ' + $(if ($reply) { 'answers' } else { 'no answer' }))
        return 0
    }
    Say 'NOT connected: 45 seconds after the restart the dongle still has no 10.35.78.x address.'
    Say 'Is the Frame on and awake (not in standby), and is Steam running on this PC?'
    Show-Failures (Get-Date).AddMinutes(-2) 'After the restart (last 2 minutes):'
    return 3
}

function Invoke-Install {
    try {
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Say 'An auto-fix is already installed: stopping and replacing it.'
            Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Start-Sleep -Seconds 2
        }
        if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir | Out-Null }
        if ($Self -ne $Installed) { Copy-Item -Path $Self -Destination $Installed -Force }
        try { Unblock-File -Path $Installed } catch {}
        Say "Copied this file to $Dir"
        $result = & icacls.exe $Dir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' 2>&1
        if ($LASTEXITCODE -ne 0) {
            Say ('ERROR: could not restrict the folder permissions: ' + ($result -join ' '))
            return 1
        }
        Say 'Folder locked: only System and Administrators can change it (everyone can read the log).'
        $arguments = '/c ""{0}" watch "{1}""' -f $Installed, $Pattern
        $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument $arguments
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
        $description = 'Restarts the Steam Frame Wi-Fi dongle when it stays disconnected while Steam is running. Log: ' + $LogFile
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $description -Force | Out-Null
        Say "Scheduled task '$TaskName' created (runs at Windows start-up, as System)."
        Start-ScheduledTask -TaskName $TaskName
        Say 'Started now: no need to restart the PC.'
    } catch {
        Say ('ERROR: ' + $_.Exception.Message)
        return 1
    }
    Start-Sleep -Seconds 6
    Say ('Task state: ' + (Get-ScheduledTask -TaskName $TaskName).State)
    if (Test-Path $LogFile) {
        Say 'Log (first lines):'
        Get-Content $LogFile -TotalCount 5 | ForEach-Object { Say ('  ' + $_) }
    } else {
        Say 'The log does not exist yet: it appears within a few seconds.'
    }
    Say "Log file: $LogFile"
    return 0
}

function Invoke-Uninstall {
    try {
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Say "Scheduled task '$TaskName' stopped and removed."
        } else {
            Say 'The auto-fix was not installed.'
        }
        if ((Test-Path $Installed) -and ($Self -ne $Installed)) {
            Remove-Item -Path $Installed -Force
            Say 'Removed the installed copy.'
        } elseif ($Self -eq $Installed) {
            Say "This is the installed copy, so it was left in place: delete $Installed yourself."
        }
        if (Test-Path $LogFile) { Say "The log was left where it is, delete it if you like: $LogFile" }
    } catch {
        Say ('ERROR: ' + $_.Exception.Message)
        return 1
    }
    return 0
}

function Invoke-Status {
    $dongle = Find-Dongle $Pattern
    if (-not $dongle) {
        Say ('No adapter matching "{0}" was found.' -f $Pattern)
        return 1
    }
    $linked = Test-Linked $dongle.Name
    Say ('Adapter: {0}, status: {1}, linked to the Frame: {2}' -f $dongle.Name, $dongle.Status, $(if ($linked) { 'yes' } else { 'no' }))
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Say ('Auto-fix: ' + $(if ($task) { 'installed (' + $task.State + ')' } else { 'not installed' }))
    return $(if ($linked) { 0 } else { 1 })
}

function Show-Menu {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host '  Frame Dongle Fix - Steam Frame Wi-Fi dongle'
    Write-Host ('  Auto-fix: ' + $(if ($task) { 'installed' } else { 'not installed' }))
    Write-Host ''
    Write-Host '  1  Fix now            restart the dongle adapter (when it will not connect)'
    Write-Host '  2  Install auto-fix   do it automatically from now on'
    Write-Host '  3  Uninstall auto-fix'
    Write-Host '  4  Quit'
    Write-Host ''
    return (Read-Host '  Choose 1-4')
}

function Invoke-Mode([string]$name) {
    if ($name -ne 'watch') { $script:Report = Open-Report }
    $code = 0
    switch ($name) {
        'watch' { Invoke-Watch }
        'fix' { $code = @(Invoke-Fix)[-1] }
        'install' { $code = @(Invoke-Install)[-1] }
        'uninstall' { $code = @(Invoke-Uninstall)[-1] }
        'status' { $code = @(Invoke-Status)[-1] }
        default {
            $choice = Show-Menu
            if ($choice -eq '1') { $code = @(Invoke-Fix)[-1] }
            elseif ($choice -eq '2') { $code = @(Invoke-Install)[-1] }
            elseif ($choice -eq '3') { $code = @(Invoke-Uninstall)[-1] }
        }
    }
    if ($script:Report) { Write-Host "Report: $($script:Report)" }
    return $code
}

if ($Mode -ne 'lib') {
    if (($Mode -ne 'watch') -and -not (Test-Admin)) {
        Write-Host 'Administrator permission is needed: right-click the file and choose Run as administrator.'
        exit 1
    }
    exit (@(Invoke-Mode $Mode)[-1])
}
