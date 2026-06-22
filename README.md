# fixf-exfat-no-dismount

PowerShell 5 tooling for repairing `F:` exFAT corruption without using `chkdsk /x`.

An `E:` variant is also available with the same behavior:

```text
scripts\fixe-exfat-no-dismount.ps1
artifacts\fixe-direct-one-liner.txt
```

The `E:` variant is shell-safe: it only treats real `type: File` handles under `E:\` as blockers, ignores unrelated shell `Section` handles, and does not terminate `explorer.exe`.

The workflow is intentionally aggressive about releasing open `F:` handles, but it avoids the `/x` forced-dismount flag. It makes the unavoidable `chkdsk /f` lock window as short as possible: stage the repair runner on `C:`, release blockers, run the repair, immediately restart preserved tools, then verify read-only after `F:` is back in normal use. It:

- Downloads Microsoft Sysinternals Handle to `C:\Temp\codex-sysinternals-handle` if missing.
- Stages the live repair script to `C:\Temp\fixf-exfat-no-dismount\fixf-exfat-no-dismount.ps1` so PowerShell is not executing the repair file from `F:`.
- Preserves `FOUND.###` recovery folders by moving them to `F:\_chkdsk_recovered_quarantine`.
- Saves handle/process state to `C:\Temp\fixf-state-*.json`.
- First switches its own working directory and process current directory to `C:\`, so the repair process does not keep `F:` open itself.
- Stops processes holding `F:` handles, excluding the current PowerShell ancestor chain.
- Closes Explorer folder windows on `F:` and restarts Explorer if Explorer folder/cache handles were blocking `F:`.
- Restarts only top-level user apps by full executable path; helper children such as `bridge32.exe`, `bridge64.exe`, and `dllhost.exe` are not restarted directly.
- Runs `chkdsk F: /f /freeorphanedchains` first and answers `n` to any forced-dismount prompt.
- Requires at least one deep `chkdsk F: /f /r /freeorphanedchains` repair pass before reporting success, so a fast clean pass alone is not treated as enough.
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

The generated `E:` launcher one-liner is written to:

```text
artifacts\fixe-direct-one-liner.txt
```

Use the generated one-liner when your prompt is already inside `F:\...`. It remembers the caller's current directory, switches to `C:\`, copies the repair script to `C:\Temp`, runs that staged copy, and restores the original directory afterward when it is reachable.

## Run the readable script

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\fixf-exfat-no-dismount.ps1
```

For `E:`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\fixe-exfat-no-dismount.ps1
```

The local profile functions `ffixf` and `ffixe` are configured outside this repository to launch the generated artifact from `C:\Temp` in a separate minimized Windows PowerShell process, move the caller prompt to `C:\`, and return control immediately. The drive can still be temporarily locked by Windows during the actual `chkdsk /f` or `/r` repair window; that lock is required by Windows for exFAT modification.

## Verification from the live repair

The proven live repair path completed with:

```text
FIXF_OK: F: clean, reachable, verified; repair lock window was limited to each repair pass
CALLER_PWD_AFTER=F:\Downloads
STOPPED explorer.exe pid=10336 pass=1
RESTART explorer.exe oldpid=10336 result=0 newpid=15648
POST_LINER_CHKDSK_EXIT=0
Volume - F: is NOT Dirty
F_REACHABLE=True
ROOT_FOUND_COUNT=0
STAGED_SCRIPT_EXISTS=True
```

After the deep-repair gate was added, the proven `F:` profile path completed with:

```text
FIXF_FAST_CLEAN_DEEP_REPAIR_STILL_REQUIRED
FIXF_REPAIR_PASS_START pass=2 mode=deep
FIXF_REPAIR_MODE deep
FIXF_OK: F: clean, reachable, deep-repair verified; repair lock window was limited to each repair pass
CALLER_PWD_AFTER=F:\Downloads
Volume - F: is NOT Dirty
F_REACHABLE=True
ROOT_FOUND_COUNT=0
```

The proven `E:` path completed with:

```text
FIXE_OK: E: clean, reachable, verified; repair lock window was limited to each repair pass
CALLER_PWD_AFTER=E:\
EXPLORER_BEFORE=12748
EXPLORER_AFTER=12748
Volume - E: is NOT Dirty
E_REACHABLE=True
ROOT_FOUND_COUNT=0
```

## Important limitation

This does not use `/x`, but Windows still requires a brief exclusive lock for `chkdsk /f` to modify an exFAT volume. The script gets as close as possible to always-available behavior by staging itself on `C:\`, clearing blockers including Explorer folder handles, repairing, restarting preserved tools immediately, then verifying after `F:` is usable again. No software-only script can guarantee repair of failed hardware or unrecoverable file contents.
