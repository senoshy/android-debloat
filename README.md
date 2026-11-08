# debloat-android

Debloat a **Samsung Galaxy A35** (One UI, Exynos 1380) over ADB from a Linux host, with **no root, no flashing and no system-partition changes**. Every change made by a run can be undone by the restore script that run generates.

> **Not affiliated with Samsung or Google.** Use at your own risk. Read the dry-run output before applying, and keep the generated restore script until you are sure the phone behaves.

## What it does

| Step | What happens | Reversible |
| --- | --- | --- |
| Packages | `pm uninstall --user 0` for **67** Samsung, Bixby, telemetry and Facebook stub packages | `cmd package install-existing <pkg>` |
| Settings | **11** privacy/battery/UI settings via `settings put` | original value restored |
| Background | **3** apps restricted with `appops` + standby bucket `restricted` | `appops ... default` + bucket `active` |

Removal is per-user (`--user 0`), so the APKs stay on the read-only system image. A factory reset or `install-existing` brings them back.

## Requirements

- Linux host with `adb` (NixOS: `programs.adb.enable = true` or the `android-tools` package is enough).
- A Galaxy A35 with **USB debugging** enabled and the host authorized.
- Samsung **Auto Blocker** → *Block commands and software updates by USB cable* must be **off** while working.
- No root. None of the commands used need it.

## Quick start

```bash
chmod +x debloat.sh
./debloat.sh --dry-run   # preview: lists what would change, touches nothing
./debloat.sh             # apply
```

Then reboot, run the [post-run checklist](#after-a-run), and keep `restore-<date>.sh` around.

The script exits without changing anything if `adb` is missing, if no device is authorized, or if more than one device is attached. To target a specific phone when several are plugged in:

```bash
ANDROID_SERIAL=<serial> ./debloat.sh
```

## Usage

```
./debloat.sh --dry-run   # does not write to the device or to the restore script
./debloat.sh             # applies the changes and writes log + restore script
```

Each run creates two files in the current directory:

- `debloat-<date>-<time>.log`: one line per action
- `restore-<date>-<time>.sh`: executable script that undoes that exact run

Both are created `0600`/`0700` (via `umask 077`) and are listed in `.gitignore`, because they record device state. Do not commit them.

### Output verbs

| Verb | Meaning |
| --- | --- |
| `REMOVED` / `REMOVIDO` | package uninstalled for user 0 |
| `SKIPPED` / `PULOU` | package not installed, nothing done |
| `FAILED` / `FALHOU` | device refused the command (message is shown) |
| `CHANGED` / `AJUSTADO` | setting written (`old -> new` is printed) |
| `RESTRICTED` / `RESTRITO` | background activity restricted |
| `REMOVERIA`, `AJUSTARIA`, `RESTRINGIRIA` | dry-run only, nothing was done |

## What gets removed

| Group | Count | Examples |
| --- | --- | --- |
| Text-to-speech | 7 | `com.samsung.SMT` and language packs |
| Games | 3 | `game.gamehome`, `game.gametools`, `game.gos` (Game Optimizing Service) |
| Bixby | 5 | `bixby.agent`, `bixby.wakeup`, `visionintelligence` |
| Samsung extras | 32 | themes, stickers, AR emoji, Watch Manager, Kids, Edge panels, DeX helpers |
| Low-risk extras | 12 | live wallpapers, media/audio mirroring, network diagnostics, Smart Switch assistant |
| Telemetry | 5 | `dqagent`, `rubin.app`, `svcagent`, `knox.analytics.uploader`, `omcagent` |
| Facebook stubs | 3 | `facebook.appmanager`, `facebook.services`, `facebook.system` |

The full list lives in `PACKAGES` at the top of `debloat.sh`, grouped by comment.

### Deliberately kept

These are **never** removed, because losing them breaks calls, updates, security or the user's daily use:

- Galaxy Store (`com.sec.android.app.samsungapps`) so Good Lock and Samsung app updates keep working
- Google Play Services and Google Speech Services
- `knox*` (except the analytics uploader), `telephony*`, `ims*`, `nfc*`, `biometrics*`, `providers.*`, `networkstack*`, `mcf*`, `dsms`, `scpm`, `ssu`, `klmsagent`, `mdm`, `sm.devicesecurity`, `honeyboard`, `systemui.navbar*`, contacts/dialer/incallui, AOD service
- User keep list: `earphonetypec`, `bluelightfilter`, `singletake.service`, `dynamiclock`, `smartcallprovider`, `gpuwatchapp`, `multisound`, `knox.securefolder`

## Settings applied

Entries are `"namespace key value"` in `SETTINGS`:

| Namespace | Key | Value | Why |
| --- | --- | --- | --- |
| secure | `accessibility_display_daltonizer_enabled` | `1` | screen becomes grayscale (monochrome) |
| secure | `accessibility_display_daltonizer` | `0` | monochrome mode used by the line above |
| secure | `limit_ad_tracking` | `1` | opt out of ad ID tracking |
| global | `send_action_app_error` | `0` | stop sending app-crash error intents |
| global | `wifi_scan_always_enabled` | `0` | no background Wi-Fi scanning for location |
| global | `ble_scan_always_enabled` | `0` | no background Bluetooth LE scanning |
| global | `private_dns_mode` | `hostname` | DNS over TLS on |
| global | `private_dns_specifier` | `dns.adguard-dns.com` | DNS provider (see [Security notes](#security-notes)) |
| global | `window_animation_scale` | `0.5` | faster UI |
| global | `transition_animation_scale` | `0.5` | faster UI |
| global | `animator_duration_scale` | `0.5` | faster UI |

## Background restrictions

Three apps get `RUN_ANY_IN_BACKGROUND ignore` and standby bucket `restricted`: LinkedIn, Samsung Account (`com.osp.app.signin`) and Shazam. They still work when opened; they just stop waking up on their own.

Side effects to expect: LinkedIn/Samsung Account sync only while open, and Samsung Account sign-in may not complete until you undo it. Undo with:

```bash
adb shell cmd appops set com.linkedin.android RUN_ANY_IN_BACKGROUND default
adb shell am set-standby-bucket com.linkedin.android active
```

## Restoring

Everything, from the latest run:

```bash
./restore-<date>-<time>.sh
```

A single package or setting:

```bash
adb shell cmd package install-existing com.samsung.SMT.lang_pt_br_f00
adb shell settings put global private_dns_mode opportunistic   # drop the pinned DNS provider
```

The restore script only undoes what its own run changed. If you ran the script several times, keep every `restore-*.sh` or use the newest one plus the single-package command above.

## After a run

Reboot, then check:

- [ ] Phone boots normally
- [ ] Calls, SMS/RCS and mobile data work
- [ ] Wi-Fi works (and apps do not fail DNS lookups)
- [ ] Camera and gallery open
- [ ] Keyboard (Samsung Keyboard) opens and types
- [ ] Fingerprint and face unlock work
- [ ] NFC works, if you use it

If something breaks, run the restore script first, then investigate one package at a time.

## Security notes

- **No root, no system writes.** Only `pm uninstall --user 0`, `settings put`, `appops` and standby-bucket commands are used. No `pm clear`, `rm`, remount or flash.
- **Ambiguous target refused.** The script aborts when more than one authorized device is connected, so a run cannot hit the wrong phone. Use `ANDROID_SERIAL` to pick one explicitly.
- **Generated files are private.** `umask 077` keeps the log and restore script readable only by you, since they contain a snapshot of device settings. They are also gitignored: never commit them or paste them in issues.
- **Restore script is shell-quoted.** Package names and setting values are written with `printf %q`, so a device-provided value cannot inject commands into the restore script when you later run it. Still read the script before executing it.
- **Private DNS goes to a third party.** `dns.adguard-dns.com` sees every lookup. If you do not want that, change `private_dns_specifier` to your resolver or use `settings put global private_dns_mode opportunistic`, which keeps DNS on the network's resolver (unencrypted).
- **ADB is a privileged channel.** Use a trusted host and cable, keep the phone unlocked while connected, and turn USB debugging off (and revoke authorizations) when finished. Do not enable wireless debugging/ADB over network on shared or public networks.
- **Auto Blocker conflict.** Auto Blocker blocks ADB by design; disabling it temporarily is a deliberate trade-off. Re-enable it afterwards.
- **Understand before applying.** Some removals are functional, not cosmetic (themes, Watch Manager, Kids, AR emoji, Smart Switch assistant). If you use a feature, delete its package from `PACKAGES` before running.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `Nenhum aparelho autorizado` | Check cable/USB mode, accept the RSA prompt on the phone, run `adb devices` |
| `Mais de um aparelho conectado` | Run `ANDROID_SERIAL=<serial> ./debloat.sh`, or unplug the extra devices |
| `adb: device unauthorized` | Revoke USB debugging authorizations, replug, accept again |
| Commands silently refused | Auto Blocker's USB-cable command blocking is on |
| Apps fail DNS or hang | `adb shell settings put global private_dns_mode opportunistic` |
| Package reappears after an update | Normal after major One UI updates, rerun the script |
| Tablet/watch/game features missing | Restore the package with `cmd package install-existing` |

## Project layout

```
debloat.sh              main script (packages, settings, restrictions, restore builder)
README.md               this file
AGENTS.md               rules for AI agents and contributors
debloat-*.log           generated per run, gitignored
restore-*.sh            generated per run, gitignored
```

## Contributing

Read [`AGENTS.md`](AGENTS.md) first. In short:

1. Confirm the package exists: `adb shell pm list packages | grep -i <name>`.
2. Check it is not in the never-remove or keep lists.
3. Add it under the right commented section of `PACKAGES` (or `SETTINGS` / `RESTRICT`).
4. Every change must append its undo line to `$RESTORE` in the same code path, and `--dry-run` must still change nothing.
5. Run `shellcheck debloat.sh` and `bash -n debloat.sh` before proposing the change.

## License

No license file yet. Add one before publishing or redistributing this script.

## Resumo em português (BR)

`debloat.sh` remove 67 pacotes da Samsung, do Bixby, de telemetria e do Facebook **só do usuário 0**, aplica 11 ajustes de privacidade/bateria e restringe 3 apps em segundo plano. Não usa root, não mexe na partição de sistema e tudo é reversível.

```bash
chmod +x debloat.sh
./debloat.sh --dry-run   # só mostra
./debloat.sh             # aplica
./restore-<data>.sh      # desfaz o que aquele run mudou
```

Depois de aplicar, reinicie e teste chamadas, dados móveis, Wi-Fi, câmera, teclado, digital e NFC. Se algo quebrar, rode o `restore-*.sh` gerado. O log e o script de restauração ficam privados (`0600`) e fora do git, porque registram o estado do aparelho. Desligue a depuração USB ao terminar.
