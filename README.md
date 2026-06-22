# fixf-exfat-no-dismount

PowerShell 5 tooling for repairing `F:` exFAT corruption without using `chkdsk /x`.

The workflow is intentionally aggressive about releasing open `F:` handles, but it avoids the `/x` forced-dismount flag. It:

- Downloads Microsoft Sysinternals Handle to `C:\Temp\codex-sysinternals-handle` if missing.
- Preserves `FOUND.###` recovery folders by moving them to `F:\_chkdsk_recovered_quarantine`.
- Saves handle/process state to `C:\Temp\fixf-state-*.json`.
- Switches its own working directory to `C:\` when launched from `F:\...`, so the repair process does not keep `F:` open itself.
- Stops processes holding `F:` handles, excluding the current PowerShell ancestor chain.
- Restarts Explorer if Explorer folder windows/cache handles were blocking `F:`.
- Runs `chkdsk F: /f /freeorphanedchains` and answers `n` to any forced-dismount prompt.
- Verifies with read-only `chkdsk F:`, `fsutil dirty query F:`, and root `FOUND.*` enumeration.
- Restarts preserved user tools by their original command lines.

## Generate the direct one-liner

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\New-FixFOneLiner.ps1
```

The generated direct launcher one-liner is written to:

```text
artifacts\fixf-direct-one-liner.txt
```

Use the generated one-liner when your prompt is already inside `F:\...`. It starts with `Set-Location -LiteralPath C:\` so the caller's own PowerShell session does not keep `F:` open during the repair.

## Run the readable script

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\fixf-exfat-no-dismount.ps1
```

## Verification from the live repair

The proven live repair path completed with:

```text
FIXF_OK: F: clean, reachable, verified without /x forced dismount
POST_LINER_CHKDSK_EXIT=0
Volume - F: is NOT Dirty
F_REACHABLE=True
```

## Important limitation

This does not use `/x`, but it does temporarily stop processes that hold open `F:` handles. That is the proven way Windows allowed `chkdsk /f` to lock and repair the exFAT volume without forced dismount.
