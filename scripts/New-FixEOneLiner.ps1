$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$scriptPath = Join-Path $projectRoot 'scripts\fixe-exfat-no-dismount.ps1'
$outPath = Join-Path $projectRoot 'artifacts\fixe-direct-one-liner.txt'

$escapedScriptPath = $scriptPath.Replace("'", "''")
$oneLiner = "`$fixePwd=(Get-Location).ProviderPath; Set-Location -LiteralPath C:\; [Environment]::CurrentDirectory='C:\'; `$fixeStage='C:\Temp\fixe-exfat-no-dismount\fixe-exfat-no-dismount.ps1'; New-Item -ItemType Directory -Path (Split-Path -Parent `$fixeStage) -Force|Out-Null; Copy-Item -LiteralPath '$escapedScriptPath' -Destination `$fixeStage -Force; & C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$fixeStage; `$fixeExit=`$LASTEXITCODE; if(`$fixePwd -and (Test-Path -LiteralPath `$fixePwd -ErrorAction SilentlyContinue)){Set-Location -LiteralPath `$fixePwd; [Environment]::CurrentDirectory=`$fixePwd}elseif(Test-Path -LiteralPath E:\ -ErrorAction SilentlyContinue){Set-Location -LiteralPath E:\; [Environment]::CurrentDirectory='E:\'}; if(`$fixeExit -ne 0){throw ('FIXE_CHILD_EXIT=' + `$fixeExit)}"

Set-Content -LiteralPath $outPath -Value $oneLiner -Encoding UTF8

$errors = $null
[System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath $scriptPath -Raw), [ref]$errors) | Out-Null
if ($errors) {
    throw "PowerShell 5 parse probe failed: $($errors | Out-String)"
}

$oneLinerErrors = $null
[System.Management.Automation.PSParser]::Tokenize($oneLiner, [ref]$oneLinerErrors) | Out-Null
if ($oneLinerErrors) {
    throw "PowerShell 5 one-liner parse probe failed: $($oneLinerErrors | Out-String)"
}

[pscustomobject]@{
    OneLinerPath = $outPath
    Length = $oneLiner.Length
    Parse = 'PS5_SCRIPT_AND_ONE_LINER_PARSE_OK'
}
