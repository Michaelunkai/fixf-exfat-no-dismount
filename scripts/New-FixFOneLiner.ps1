$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$scriptPath = Join-Path $projectRoot 'scripts\fixf-exfat-no-dismount.ps1'
$outPath = Join-Path $projectRoot 'artifacts\fixf-direct-one-liner.txt'

$escapedScriptPath = $scriptPath.Replace("'", "''")
$oneLiner = "`$fixfPwd=(Get-Location).ProviderPath; Set-Location -LiteralPath C:\; [Environment]::CurrentDirectory='C:\'; `$fixfStage='C:\Temp\fixf-exfat-no-dismount\fixf-exfat-no-dismount.ps1'; New-Item -ItemType Directory -Path (Split-Path -Parent `$fixfStage) -Force|Out-Null; Copy-Item -LiteralPath '$escapedScriptPath' -Destination `$fixfStage -Force; & C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$fixfStage; `$fixfExit=`$LASTEXITCODE; if(`$fixfPwd -and (Test-Path -LiteralPath `$fixfPwd -ErrorAction SilentlyContinue)){Set-Location -LiteralPath `$fixfPwd; [Environment]::CurrentDirectory=`$fixfPwd}elseif(Test-Path -LiteralPath F:\ -ErrorAction SilentlyContinue){Set-Location -LiteralPath F:\; [Environment]::CurrentDirectory='F:\'}; if(`$fixfExit -ne 0){throw ('FIXF_CHILD_EXIT=' + `$fixfExit)}"

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
