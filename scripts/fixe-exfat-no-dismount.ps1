$originalLocation = (Get-Location).ProviderPath
Set-Location -LiteralPath 'C:\'
[Environment]::CurrentDirectory = 'C:\'
$ErrorActionPreference = 'Stop'

$driveLetter = 'E'
$drive = $driveLetter + ':'
$root = $drive + '\'
$handle = 'C:\Temp\codex-sysinternals-handle\handle64.exe'
$statePrefix = 'fixe-state'

if (!(Test-Path -LiteralPath $root)) {
    throw ($drive + ' is not reachable')
}

if (!(Test-Path -LiteralPath $handle)) {
    $handleDir = Split-Path -Parent $handle
    New-Item -ItemType Directory -Path $handleDir -Force | Out-Null
    $zip = Join-Path $handleDir 'Handle.zip'
    (New-Object Net.WebClient).DownloadFile('https://download.sysinternals.com/files/Handle.zip', $zip)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $handleDir)
}

$noRestartNames = @('powershell.exe', 'pwsh.exe', 'adb.exe', 'docker-buildx.exe', 'dllhost.exe', 'bridge32.exe', 'bridge64.exe', 'conhost.exe', 'handle64.exe', 'handle.exe')

function Get-FixEAncestorPids {
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
    $ancestors
}

function Reset-FixERestartQueue {
    $script:FixERestart = @()
    $script:FixESeenRestart = @{}
}

function Add-FixERestartCandidate {
    param(
        [Parameter(Mandatory = $true)]$Process,
        [switch]$Explorer
    )

    if ($Explorer) {
        if (!$script:FixESeenRestart.ContainsKey('explorer.exe')) {
            $script:FixERestart += [pscustomobject]@{
                ProcessId = $Process.ProcessId
                ParentProcessId = $Process.ParentProcessId
                Name = 'explorer.exe'
                ExecutablePath = 'C:\Windows\explorer.exe'
                CommandLine = 'C:\Windows\explorer.exe'
            }
            $script:FixESeenRestart['explorer.exe'] = $true
        }
        return
    }

    if (!$Process.ExecutablePath -or $Process.Name -in $script:noRestartNames -or $Process.Name -eq 'explorer.exe') {
        return
    }

    $restartKey = $Process.ExecutablePath + '|' + $Process.CommandLine
    if (!$script:FixESeenRestart.ContainsKey($restartKey)) {
        $script:FixERestart += $Process
        $script:FixESeenRestart[$restartKey] = $true
    }
}

function Restart-FixESavedProcesses {
    foreach ($process in $script:FixERestart) {
        if ($process.CommandLine -or $process.ExecutablePath) {
            try {
                $commandLine = $process.CommandLine
                if (!$commandLine -or ($process.ExecutablePath -and $commandLine -notmatch '^[A-Za-z]:\\|^"')) {
                    $commandLine = '"' + $process.ExecutablePath + '"'
                }
                $result = ([wmiclass]'Win32_Process').Create($commandLine, 'C:\', $null)
                Write-Host ('RESTART ' + $process.Name + ' oldpid=' + $process.ProcessId + ' result=' + $result.ReturnValue + ' newpid=' + $result.ProcessId)
            } catch {
                Write-Host ('RESTART_FAIL ' + $process.Name + ' oldpid=' + $process.ProcessId + ' ' + $_.Exception.Message)
            }
        }
    }
    Reset-FixERestartQueue
}

function Close-FixEExplorerWindows {
    try {
        $shell = New-Object -ComObject Shell.Application
        foreach ($window in @($shell.Windows())) {
            try {
                $path = $window.Document.Folder.Self.Path
                if ($path -eq $script:root -or $path -like ($script:root + '*')) {
                    Write-Host ('EXPLORER_WINDOW_CLOSE ' + $path)
                    $window.Quit()
                }
            } catch {
            }
        }
    } catch {
        Write-Host ('EXPLORER_WINDOW_CLOSE_SKIP ' + $_.Exception.Message)
    }
}

function Move-FixEFoundFolders {
    param(
        [Parameter(Mandatory = $true)][string]$Stamp
    )

    $quarantine = Join-Path $root '_chkdsk_recovered_quarantine'
    Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.PSIsContainer -and $_.Name -match '^FOUND\.\d{3}$' } |
        ForEach-Object {
            New-Item -ItemType Directory -Path $quarantine -Force | Out-Null
            $destination = Join-Path $quarantine ($Stamp + '_' + $_.Name)
            Move-Item -LiteralPath $_.FullName -Destination $destination -ErrorAction Stop
            Write-Host ('QUARANTINED ' + $destination)
        }
}

function Release-FixEHandles {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ancestors,
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)][int]$RepairPass
    )

    $all = @()
    $handlesClear = $false
    for ($pass = 1; $pass -le 16; $pass++) {
        $handles = & $handle -accepteula -nobanner $drive 2>&1
        if (($handles -join "`n") -match 'No matching handles found') {
            Write-Host ('HANDLE_CLEAR repairPass=' + $RepairPass + ' releasePass=' + $pass)
            $handlesClear = $true
            break
        }

        $handlePids = @{}
        foreach ($line in $handles) {
            if ($line -match 'pid:\s*(\d+)') {
                $handlePids[[int]$matches[1]] = $true
            }
        }

        $explorerHasDriveHandle = $false
        foreach ($line in $handles) {
            if ($line -match '^explorer\.exe\s+pid:') {
                $explorerHasDriveHandle = $true
                break
            }
        }
        if ($explorerHasDriveHandle) {
            Close-FixEExplorerWindows
        }

        $processes = @(Get-CimInstance Win32_Process |
            Where-Object {
                (!$Ancestors.ContainsKey([int]$_.ProcessId) -or $_.Name -eq 'explorer.exe') -and
                ($handlePids.ContainsKey([int]$_.ProcessId) -or $_.ExecutablePath -like ($root + '*') -or $_.CommandLine -like ('*' + $root + '*'))
            } |
            Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine)

        $selected = @{}
        foreach ($process in $processes) {
            $selected[[int]$process.ProcessId] = $process
        }

        foreach ($process in @($processes)) {
            $parentId = [int]$process.ParentProcessId
            while ($parentId -and !$Ancestors.ContainsKey($parentId) -and !$selected.ContainsKey($parentId)) {
                $parent = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $parentId) -ErrorAction SilentlyContinue |
                    Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine
                if (!$parent) {
                    break
                }
                if ($parent.ExecutablePath -like ($root + '*') -or $parent.CommandLine -like ('*' + $root + '*')) {
                    $selected[[int]$parent.ProcessId] = $parent
                    $processes += $parent
                    $parentId = [int]$parent.ParentProcessId
                } else {
                    break
                }
            }
        }

        $processes = @($processes | Sort-Object ProcessId -Unique)
        $selectedIds = @{}
        foreach ($process in $processes) {
            $selectedIds[[int]$process.ProcessId] = $true
        }

        $all += $processes
        foreach ($process in $processes) {
            $isChildOfSelectedProcess = $selectedIds.ContainsKey([int]$process.ParentProcessId)
            if (!$isChildOfSelectedProcess) {
                Add-FixERestartCandidate -Process $process
            }
            if ($process.Name -eq 'explorer.exe') {
                Add-FixERestartCandidate -Process $process -Explorer
            }
        }

        [pscustomobject]@{
            CreatedAt = (Get-Date).ToString('o')
            Pass = $pass
            RepairPass = $RepairPass
            HandleOutput = $handles
            Processes = $all
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $StatePath -Encoding UTF8

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
        $last = & $handle -accepteula -nobanner $drive 2>&1
        if (($last -join "`n") -notmatch 'No matching handles found') {
            $last
            throw ($drive + ' still has open handles after release loop; repair not attempted.')
        }
        Write-Host ('HANDLE_CLEAR repairPass=' + $RepairPass + ' final-check')
    }
}

function Invoke-FixERepair {
    param(
        [Parameter(Mandatory = $true)][string]$Mode
    )

    Push-Location C:\
    try {
        if ($Mode -eq 'deep') {
            $command = 'echo n|C:\Windows\System32\chkdsk.exe ' + $drive + ' /f /r /freeorphanedchains'
        } else {
            $command = 'echo n|C:\Windows\System32\chkdsk.exe ' + $drive + ' /f /freeorphanedchains'
        }
        Write-Host ('FIXE_REPAIR_MODE ' + $Mode)
        $repair = cmd /c $command 2>&1
        $repair
        $repairText = $repair -join "`n"
        if ($repairText -match 'Cannot lock|cannot continue in read-only mode|Access is denied|Cannot open volume') {
            throw ('FIXE_REPAIR_LOCK_FAILED: chkdsk could not lock ' + $drive + ' after handle release.')
        }
    } finally {
        Pop-Location
    }
}

function Test-FixEClean {
    Push-Location C:\
    try {
        $verify = & C:\Windows\System32\chkdsk.exe $drive 2>&1
        $verifyText = $verify -join "`n"
        $verify

        $dirty = (& fsutil dirty query $drive 2>&1) -join "`n"
        $dirty

        if ($verifyText -match 'Corruption was found|found errors|found problems|Run CHKDSK with the /F' -or $dirty -notmatch 'NOT Dirty') {
            Write-Host 'FIXE_VERIFY_STILL_CORRUPT'
            return $false
        }

        if (Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer -and $_.Name -like 'FOUND.*' }) {
            Write-Host 'FIXE_VERIFY_FOUND_FOLDERS_REMAIN'
            return $false
        }

        return $true
    } finally {
        Pop-Location
    }
}

function Restore-FixEOriginalLocation {
    if ($script:originalLocation -and (Test-Path -LiteralPath $script:originalLocation -ErrorAction SilentlyContinue)) {
        Set-Location -LiteralPath $script:originalLocation
        [Environment]::CurrentDirectory = $script:originalLocation
    } elseif (Test-Path -LiteralPath $script:root -ErrorAction SilentlyContinue) {
        Set-Location -LiteralPath $script:root
        [Environment]::CurrentDirectory = $script:root
    }
}

try {
    $ancestors = Get-FixEAncestorPids
    $maxRepairPasses = 6
    $clean = $false

    for ($repairPass = 1; $repairPass -le $maxRepairPasses; $repairPass++) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $state = "C:\Temp\$statePrefix-$stamp-pass$repairPass.json"
        Reset-FixERestartQueue

        $repairMode = if ($repairPass -ge 2) { 'deep' } else { 'fast' }

        Write-Host ('FIXE_REPAIR_PASS_START pass=' + $repairPass + ' mode=' + $repairMode)
        try {
            Move-FixEFoundFolders -Stamp $stamp
            Release-FixEHandles -Ancestors $ancestors -StatePath $state -RepairPass $repairPass
            Invoke-FixERepair -Mode $repairMode
        } finally {
            Restart-FixESavedProcesses
        }

        Write-Host ('FIXE_VERIFY_AFTER_RESTART pass=' + $repairPass)
        if (Test-FixEClean) {
            $clean = $true
            break
        }

        Start-Sleep -Seconds 2
    }

    if (!$clean) {
        throw ('FIXE_FAILED: corruption remains after ' + $maxRepairPasses + ' shortest-lock repair passes.')
    }

    'FIXE_OK: ' + $drive + ' clean, reachable, verified; repair lock window was limited to each repair pass'
} finally {
    try {
        Restore-FixEOriginalLocation
    } catch {
        Write-Host ('RESTORE_LOCATION_SKIP ' + $_.Exception.Message)
    }
}
