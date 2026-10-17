. (Join-Path $PSScriptRoot 'Helpers.ps1')
$ctx = Initialize-Test 'common'
. ([scriptblock]::Create((Get-Payload $ctx.Cmd)))

$raw = 'Network Adapter: Realtek Interface GUID: {314a8ba5-84e7-4c7d-a970-a6391163a5c9} Local MAC Address: 1A-2B-3C-4D-5E-6F Profile Name: frame_C050229D_3 SSID: frame_C050229D'
$clean = Hide-Private $raw
Check ($clean -notmatch '314a8ba5') 'the interface GUID is hidden'
Check ($clean -notmatch '1A-2B-3C') 'the MAC address is hidden'
Check ($clean -notmatch 'C050229D') 'the hotspot name suffix is hidden'
Check ($clean -match 'frame_XXXXXXXX_3' -and $clean -match '\{GUID\}') 'the rest of the line is kept'
Check ((Hide-Private '10.35.78.23') -eq '10.35.78.23') 'plain addresses are kept'

$Report = Open-Report
Say 'ssid frame_ABCDEF12 ok'
Check ($Report -eq (Join-Path $ctx.Root 'Frame-Dongle-Fix-report.txt')) 'the report is created next to the file'
Check ((Get-Content $Report -Raw) -match 'frame_XXXXXXXX ok') 'the report never contains the real hotspot name'

Check ($Pattern -eq '8832CU|Valve') 'the default adapter pattern is the Valve dongle'
Remove-Item $ctx.Root -Recurse -Force
Finish
