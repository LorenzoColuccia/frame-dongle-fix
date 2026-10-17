$here = $PSScriptRoot
$shellPath = (Get-Process -Id $PID).Path
$failed = 0
foreach ($file in 'Common', 'Watcher', 'Loop', 'Install', 'FixNow') {
    Write-Host "=== $file"
    & $shellPath -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here "$file.tests.ps1")
    if ($LASTEXITCODE -ne 0) { $failed++ }
}
Write-Host ''
if ($failed -eq 0) { Write-Host 'ALL TEST FILES PASSED' } else { Write-Host "$failed TEST FILES FAILED" }
exit $failed
