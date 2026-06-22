Set-Location -LiteralPath 'C:\'
[Environment]::CurrentDirectory = 'C:\'
$ErrorActionPreference = 'Stop'

$drive = 'F:'
$root = 'F:\'
$handle = 'C:\Temp\codex-sysinternals-handle\handle64.exe'

if (!(Test-Path -LiteralPath $root)) {
    throw 'F: is not reachable'
}

if (!(Test-Path -LiteralPath $handle)) {
    $handleDir = Split-Path -Parent $handle
    New-Item -ItemType Directory -Path $handleDir -Force | Out-Null
    $zip = Join-Path $handleDir 'Handle.zip'
    (New-Object Net.WebClient).DownloadFile('https://download.sysinternals.com/files/Handle.zip', $zip)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $handleDir)
}

$ancestors = @{}
$currentPid = $PID
while ($currentPid) {
    $ancestors[[int]$currentPid] = $true
    $process = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $currentPid) -ErrorAction SilentlyContinue
    if (!$process -or !$process.ParentProcessId -or $ancestors.ContainsKey([int]$process.ParentProcessId)) {
        break
    }
    $currentPid = [int]$process.ParentProcessId
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$state = "C:\Temp\fixf-state-$stamp.json"
$restart = @()
$seen = @{}
$all = @()

$quarantine = Join-Path $root '_chkdsk_recovered_quarantine'
Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.PSIsContainer -and $_.Name -match '^FOUND\.\d{3}$' } |
    ForEach-Object {
        New-Item -ItemType Directory -Path $quarantine -Force | Out-Null
        $destination = Join-Path $quarantine ($stamp + '_' + $_.Name)
        Move-Item -LiteralPath $_.FullName -Destination $destination -ErrorAction Stop
        Write-Host ('QUARANTINED ' + $destination)
    }

try {
    $handlesClear = $false
    for ($pass = 1; $pass -le 16; $pass++) {
        $handles = & $handle -accepteula -nobanner F: 2>&1
        if (($handles -join "`n") -match 'No matching handles found') {
            Write-Host ('HANDLE_CLEAR pass=' + $pass)
            $handlesClear = $true
            break
        }

        $handlePids = @{}
        foreach ($line in $handles) {
            if ($line -match 'pid:\s*(\d+)') {
                $handlePids[[int]$matches[1]] = $true
            }
        }

        $processes = Get-CimInstance Win32_Process |
            Where-Object {
                !$ancestors.ContainsKey([int]$_.ProcessId) -and
                ($handlePids.ContainsKey([int]$_.ProcessId) -or $_.ExecutablePath -like 'F:\*' -or $_.CommandLine -like '*F:\*')
            } |
            Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine

        $all += $processes
        foreach ($process in $processes) {
            if ($process.CommandLine -and $process.Name -notin @('powershell.exe', 'pwsh.exe', 'adb.exe', 'docker-buildx.exe', 'explorer.exe') -and !$seen.ContainsKey($process.CommandLine)) {
                $restart += $process
                $seen[$process.CommandLine] = $true
            }
            if ($process.Name -eq 'explorer.exe' -and !$seen.ContainsKey('explorer.exe')) {
                $restart += [pscustomobject]@{
                    ProcessId = $process.ProcessId
                    ParentProcessId = $process.ParentProcessId
                    Name = 'explorer.exe'
                    ExecutablePath = 'C:\Windows\explorer.exe'
                    CommandLine = 'C:\Windows\explorer.exe'
                }
                $seen['explorer.exe'] = $true
            }
        }

        [pscustomobject]@{
            CreatedAt = (Get-Date).ToString('o')
            Pass = $pass
            HandleOutput = $handles
            Processes = $all
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $state -Encoding UTF8

        foreach ($process in ($processes | Sort-Object ProcessId -Descending)) {
            try {
                Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
                Write-Host ('STOPPED ' + $process.Name + ' pid=' + $process.ProcessId + ' pass=' + $pass)
            } catch {
                Write-Host ('STOP_SKIP ' + $process.Name + ' pid=' + $process.ProcessId + ' ' + $_.Exception.Message)
            }
        }

        Start-Sleep -Seconds 2
    }

    if (!$handlesClear) {
        $last = & $handle -accepteula -nobanner F: 2>&1
        if (($last -join "`n") -notmatch 'No matching handles found') {
            $last
            throw 'F: still has open handles after release loop; repair not attempted.'
        }
        Write-Host 'HANDLE_CLEAR final-check'
    }

    Push-Location C:\
    try {
        $repair = cmd /c "echo n|C:\Windows\System32\chkdsk.exe F: /f /freeorphanedchains" 2>&1
        $repair

        $verify = & C:\Windows\System32\chkdsk.exe F: 2>&1
        $verifyText = $verify -join "`n"
        $verify

        $dirty = (& fsutil dirty query F: 2>&1) -join "`n"
        $dirty

        if ($verifyText -match 'Corruption was found|found errors|found problems|Run CHKDSK with the /F' -or $dirty -notmatch 'NOT Dirty') {
            throw 'FIXF_FAILED: corruption remains after no-/x repair.'
        }

        if (Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer -and $_.Name -like 'FOUND.*' }) {
            throw 'FIXF_FAILED: root FOUND.* folders remain.'
        }

        'FIXF_OK: F: clean, reachable, verified without /x forced dismount'
    } finally {
        Pop-Location
    }
} finally {
    foreach ($process in $restart) {
        if ($process.CommandLine) {
            try {
                $result = ([wmiclass]'Win32_Process').Create($process.CommandLine, 'C:\', $null)
                Write-Host ('RESTART ' + $process.Name + ' oldpid=' + $process.ProcessId + ' result=' + $result.ReturnValue + ' newpid=' + $result.ProcessId)
            } catch {
                Write-Host ('RESTART_FAIL ' + $process.Name + ' oldpid=' + $process.ProcessId + ' ' + $_.Exception.Message)
            }
        }
    }
}
