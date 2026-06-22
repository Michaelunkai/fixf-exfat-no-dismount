# fixf-exfat-no-dismount

PowerShell 5 tooling for repairing `F:` exFAT corruption without using `chkdsk /x`.

The workflow is intentionally aggressive about releasing open `F:` handles, but it avoids the `/x` forced-dismount flag. It makes the unavoidable `chkdsk /f` lock window as short as possible: release blockers, run the repair, immediately restart preserved tools, then verify read-only after `F:` is back in normal use. It:

- Downloads Microsoft Sysinternals Handle to `C:\Temp\codex-sysinternals-handle` if missing.
- Preserves `FOUND.###` recovery folders by moving them to `F:\_chkdsk_recovered_quarantine`.
- Saves handle/process state to `C:\Temp\fixf-state-*.json`.
- First switches its own working directory and process current directory to `C:\`, so the repair process does not keep `F:` open itself.
- Stops processes holding `F:` handles, excluding the current PowerShell ancestor chain.
- Restarts Explorer if Explorer folder windows/cache handles were blocking `F:`.
- Restarts only top-level user apps by full executable path; helper children such as `bridge32.exe`, `bridge64.exe`, and `dllhost.exe` are not restarted directly.
- Runs `chkdsk F: /f /freeorphanedchains` and answers `n` to any forced-dismount prompt.
- Immediately restarts preserved user tools by their original command lines after each repair attempt.
- Verifies with read-only `chkdsk F:`, `fsutil dirty query F:`, and root `FOUND.*` enumeration after restart.
- Repeats the short repair window up to 6 times only if verification still reports corruption.

## Generate the direct one-liner

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\New-FixFOneLiner.ps1
```

The generated direct launcher one-liner is written to:

```text
artifacts\fixf-direct-one-liner.txt
```

Use the generated one-liner when your prompt is already inside `F:\...`. It remembers the caller's current directory, switches to `C:\` so the caller's own PowerShell session does not keep `F:` open during the repair, and restores the original directory afterward when it is reachable.

## Run the readable script

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\fixf-exfat-no-dismount.ps1
```

## Verification from the live repair

The proven live repair path completed with:

```text
FIXF_OK: F: clean, reachable, verified; repair lock window was limited to each repair pass
CALLER_PWD_AFTER=F:\Downloads
POST_LINER_CHKDSK_EXIT=0
Volume - F: is NOT Dirty
F_REACHABLE=True
ROOT_FOUND_COUNT=0
```

## Important limitation

This does not use `/x`, but Windows still requires a brief exclusive lock for `chkdsk /f` to modify an exFAT volume. The script gets as close as possible to always-available behavior by moving itself to `C:\`, clearing blockers, repairing, restarting preserved tools immediately, then verifying after `F:` is usable again.
