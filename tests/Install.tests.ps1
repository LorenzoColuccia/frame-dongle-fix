. (Join-Path $PSScriptRoot 'Helpers.ps1')
$ctx = Initialize-Test 'install'
. ([scriptblock]::Create((Get-Payload $ctx.Cmd)))
function Test-Admin { return $true }

$global:Task = $null
$global:Calls = New-Object System.Collections.ArrayList
function Get-ScheduledTask { param([Parameter(ValueFromRemainingArguments)]$a) return $global:Task }
function New-ScheduledTaskAction { param($Execute, $Argument) [void]$global:Calls.Add("action: $Execute $Argument"); return 'A' }
function New-ScheduledTaskTrigger { param([switch]$AtStartup) [void]$global:Calls.Add('trigger: AtStartup'); return 'T' }
function New-ScheduledTaskPrincipal { param($UserId, $LogonType, $RunLevel) [void]$global:Calls.Add("principal: $UserId $LogonType $RunLevel"); return 'P' }
function New-ScheduledTaskSettingsSet { param([switch]$AllowStartIfOnBatteries, [switch]$DontStopIfGoingOnBatteries, [switch]$StartWhenAvailable, $ExecutionTimeLimit, $RestartCount, $RestartInterval, $MultipleInstances) [void]$global:Calls.Add("settings: limit=$ExecutionTimeLimit multi=$MultipleInstances"); return 'S' }
function New-TimeSpan { param($Minutes) return [TimeSpan]::FromMinutes($Minutes) }
function Register-ScheduledTask { param($TaskName, $Action, $Trigger, $Principal, $Settings, $Description, [switch]$Force) $global:Task = [pscustomobject]@{ State = 'Ready' }; [void]$global:Calls.Add("register: $TaskName") }
function Unregister-ScheduledTask { param($TaskName, $Confirm) $global:Task = $null; [void]$global:Calls.Add("unregister: $TaskName") }
function Stop-ScheduledTask { param([Parameter(ValueFromRemainingArguments)]$a) [void]$global:Calls.Add('stop') }
function Start-ScheduledTask { param([Parameter(ValueFromRemainingArguments)]$a) $global:Task.State = 'Running'; [void]$global:Calls.Add('start'); Set-Content -Path $LogFile -Value 'started' }
function icacls.exe { $global:LASTEXITCODE = 0; [void]$global:Calls.Add('icacls: ' + ($args -join ' ')) }
function Start-Sleep { param($Seconds) }

$Pattern = 'MyDongle'
$code = @(Invoke-Install)[-1]
$joined = $global:Calls -join "`n"
Check ($code -eq 0) 'the installer finishes without error'
Check (Test-Path $Installed) 'this file is copied to the program data folder'
Check ($joined -match 'icacls: .*FrameDongleFix /inheritance:r /grant:r \*S-1-5-18:\(OI\)\(CI\)F \*S-1-5-32-544:\(OI\)\(CI\)F \*S-1-5-32-545:\(OI\)\(CI\)RX') 'the folder is locked to System and Administrators (read for users)'
Check ($joined -match 'action: cmd\.exe /c ""[^"]*Frame-Dongle-Fix\.cmd" watch "MyDongle""') 'the task runs the installed copy in watch mode with the chosen pattern'
Check ($joined -match 'principal: SYSTEM ServiceAccount Highest') 'the task runs as System'
Check ($joined -match 'trigger: AtStartup' -and $joined -match 'limit=00:00:00') 'the task starts with Windows and has no time limit'
Check ($joined -match 'start') 'the task is started right away'

$global:Calls.Clear()
$code = @(Invoke-Install)[-1]
$joined = $global:Calls -join "`n"
Check ($code -eq 0 -and $joined -match 'stop' -and $joined -match 'unregister: Frame Dongle Fix' -and $joined -match 'register: Frame Dongle Fix') 'a second install replaces the first'

$global:Calls.Clear()
$code = @(Invoke-Uninstall)[-1]
Check ($code -eq 0 -and ($global:Calls -join "`n") -match 'unregister: Frame Dongle Fix') 'uninstall removes the task'
Check (-not (Test-Path $Installed)) 'uninstall removes the installed copy'
Check (Test-Path $LogFile) 'uninstall leaves the log'

$null = Invoke-Install
$Self = $Installed
$null = Invoke-Uninstall
Check (Test-Path $Installed) 'uninstall run from the installed copy does not delete the file it is running from'

Remove-Item $ctx.Root -Recurse -Force
Finish
