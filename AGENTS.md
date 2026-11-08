# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project

`debloat.sh` is a Bash script that debloats a Samsung Galaxy A35 (One UI, Exynos 1380) over ADB from a Linux host (NixOS). It does three things:

1. Removes Samsung/Facebook/telemetry packages for user 0 only (`pm uninstall --user 0`). Nothing touches the system partition, and every removal is reversible.
2. Applies privacy and battery settings (`settings put ...`).
3. Restricts background activity for chosen apps (`appops` + standby bucket).

Every run writes a log (`debloat-<date>.log`) and a restore script (`restore-<date>.sh`) that undoes exactly what that run changed.

## Repository layout

- `debloat.sh`: the script (main deliverable)
- `README.md`: user-facing docs (setup, what changes, restore, security notes)
- `debloat-*.log`, `restore-*.sh`: generated per run, do not edit or commit
- `AGENTS.md`: this file

## Environment

- Host: Linux (NixOS). `adb` comes from `android-tools` / `programs.adb.enable`.
- Target: Galaxy A35, USB debugging on, Auto Blocker's "Block commands and software updates by USB cable" off while working.
- No root on the device. Never suggest or require it.
- The device may lose its ADB authorization after a reboot. Check with `adb devices` before blaming the script.
- The script aborts if no device or more than one authorized device is attached. Use `ANDROID_SERIAL=<serial> ./debloat.sh` to pick one.

## Commands

```bash
chmod +x debloat.sh
./debloat.sh --dry-run   # preview only, changes nothing
./debloat.sh             # apply
shellcheck debloat.sh    # lint (run before proposing changes)
bash -n debloat.sh       # syntax check
```

Always run `--dry-run` first and read its output before applying.

## Script structure

- `PACKAGES=(...)`: packages to remove, grouped by comment (TTS, games, Bixby, Samsung bloat, extras, telemetry, Facebook stubs).
- `SETTINGS=(...)`: entries as `"namespace key value"` (e.g. `"global wifi_scan_always_enabled 0"`).
- `RESTRICT=(...)`: packages to restrict in the background.
- `INSTALLED`: cached `pm list packages --user 0`, used to skip packages that are not present.
- `$RESTORE`: restore script built as the run goes.

## Rules for changes

### Safety (most important)

- **Never remove** packages matching: `knox*` (except `knox.securefolder`, which is allowed), `telephony*`, `ims*`, `nfc*`, `biometrics*`, `authfw`, `networkstack*`, `wifi.*.resources`, `providers.*`, `mdm`, `klmsagent`, `kgclient`, `sm.devicesecurity`, `lool`, `honeyboard`, `mcf*`, `dsms`, `scpm`, `ssu`, `sec.android.application.csc`, `app.updatecenter`, `oda`, `smartface`, `faceservice`, `emergency`, `app.aodservice`, `systemui.navbar*`, `com.samsung.android.app.contacts`/`dialer`/`incallui`.
- **Keep Galaxy Store** (`com.sec.android.app.samsungapps`) so Good Lock and Samsung app updates keep working.
- **Keep Google Play Services** and Google's Speech Services.
- **User-chosen keep list** (never add to `PACKAGES`): `earphonetypec`, `bluelightfilter`, `singletake.service`, `dynamiclock`, `smartcallprovider`, `gpuwatchapp`, `multisound`, `knox.securefolder`.
- Prefer `pm uninstall --user 0` or `pm disable-user` over anything destructive. Never use `pm clear`, `rm`, remount, or flash commands.
- Do not touch `adb_enabled` inside the script: turning off USB debugging mid-run kills the connection. The user does that manually at the end.

### Reversibility

- Every state change must append its undo to `$RESTORE` in the same code path:
  - package removal -> `adb shell cmd package install-existing <pkg>`
  - setting change -> `settings put` with the **original** value, or `settings delete` if it was `null`
  - background restriction -> `appops ... default` and `am set-standby-bucket ... active`
- Read the old value **before** writing a new one.
- Write undo lines with `printf ... %q` (never raw `"$pkg"` / `'$old'` interpolation): package names and setting values come from the device and must not be able to inject commands into the restore script.
- A change without an undo line is a bug.

### Generated files

- `umask 077` keeps `debloat-*.log` and `restore-*.sh` private (they record device state). Keep it that way, and never commit or paste them.

### Dry-run

- `--dry-run` must change nothing on the device and write nothing to `$RESTORE`. Any new section must honor the `DRY` flag.

### Style

- Bash with `set -u`. Quote all expansions. Strip `\r` from `adb` output (`tr -d '\r'`).
- Check that a package exists (`grep -qxF` against `$INSTALLED`) before acting on it.
- Print one line per action to the terminal and the log (`tee -a "$LOG"`), with a clear verb: REMOVED / SKIPPED / FAILED / CHANGED / RESTRICTED.
- Keep comments short. Group new packages under an existing section or a new commented one.
- The user reads Portuguese (Brazil) and English. Script output is in Portuguese, code and comments in English or Portuguese, but stay consistent within the file.

### Adding packages

1. Confirm the package name against `adb shell pm list packages | grep -i <name>`.
2. Check it is not in the "never remove" or "keep" lists above.
3. Add it to the right section of `PACKAGES`, with a comment if the purpose is not obvious.
4. Run `--dry-run`, then apply, reboot, and test calls, mobile data, camera, keyboard, fingerprint, NFC.

## Testing checklist after a real run

- Phone boots normally
- Calls and SMS/RCS work
- Mobile data and Wi-Fi work
- Camera and gallery open
- Keyboard works
- Fingerprint/face unlock works
- Private DNS does not break apps (if broken: `settings put global private_dns_mode opportunistic`)

If something breaks: run the latest `restore-*.sh`, or restore a single package with `adb shell cmd package install-existing <pkg>`.

## Known limitations

- Removed packages can come back after major One UI updates; just rerun the script.
- Some `settings` keys (for example `icon_blacklist`) may be ignored by One UI.
- Telemetry that lives in `knox*`, `mcf*`, `dsms`, `scpm`, `ssu`, `klmsagent` is intentionally left alone because removing it risks boot, modem or update failures.

## Agent behavior

- Explain what a command does before suggesting it, and say how to undo it.
- Do not run `adb` commands against the device unless the user asks. Propose them instead.
- If unsure whether a package is safe, say so and recommend `disable-user` over `uninstall`.
- Do not claim the script works without having run `shellcheck` and `bash -n`.
