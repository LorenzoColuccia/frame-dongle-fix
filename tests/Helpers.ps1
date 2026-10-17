$script:Failures = 0

function Check([bool]$condition, [string]$name) {
    if ($condition) { Write-Host "ok   $name" } else { Write-Host "FAIL $name"; $script:Failures++ }
}

function Initialize-Test([string]$name) {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("fdf-{0}-{1}" -f $name, [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $root | Out-Null
    $cmd = Join-Path $root 'Frame-Dongle-Fix.cmd'
    Copy-Item (Join-Path $PSScriptRoot '../Frame-Dongle-Fix.cmd') $cmd
    $env:FDF_MODE = 'lib'
    $env:FDF_SELF = $cmd
    $env:FDF_PATTERN = ''
    $env:ProgramData = Join-Path $root 'ProgramData'
    New-Item -ItemType Directory -Path $env:ProgramData | Out-Null
    return @{ Root = $root; Cmd = $cmd }
}

function Get-Payload([string]$cmd) {
    $text = [System.IO.File]::ReadAllText($cmd)
    return $text.Substring($text.IndexOf('#PAY' + 'LOAD#'))
}

function Finish {
    Write-Host ''
    if ($script:Failures -eq 0) { Write-Host 'ALL OK' } else { Write-Host ("{0} CHECKS FAILED" -f $script:Failures) }
    exit $script:Failures
}
