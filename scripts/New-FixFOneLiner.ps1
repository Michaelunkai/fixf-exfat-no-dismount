$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$scriptPath = Join-Path $projectRoot 'scripts\fixf-exfat-no-dismount.ps1'
$outPath = Join-Path $projectRoot 'artifacts\fixf-direct-one-liner.txt'

$oneLiner = "Set-Location -LiteralPath C:\; [Environment]::CurrentDirectory='C:\'; & C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

Set-Content -LiteralPath $outPath -Value $oneLiner -Encoding UTF8

$errors = $null
[System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath $scriptPath -Raw), [ref]$errors) | Out-Null
if ($errors) {
    throw "PowerShell 5 parse probe failed: $($errors | Out-String)"
}

[pscustomobject]@{
    OneLinerPath = $outPath
    Length = $oneLiner.Length
    Parse = 'PS5_PARSE_OK'
}
