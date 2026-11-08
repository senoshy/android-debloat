#!/usr/bin/env bash
# Galaxy A35: debloat + tweaks de privacidade
# Uso: ./debloat.sh --dry-run   (apenas mostra)
#      ./debloat.sh             (aplica)
set -u
# Log and restore script stay readable only by the current user.
umask 077

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

STAMP="$(date +%F-%H%M)"
LOG="debloat-$STAMP.log"
RESTORE="restore-$STAMP.sh"

command -v adb >/dev/null || { echo "adb não encontrado"; exit 1; }

# Refuse to guess the target: exactly one authorized device, unless ANDROID_SERIAL is set.
mapfile -t DEVICES < <(adb devices | tr -d '\r' | awk 'NR > 1 && $2 == "device" { print $1 }')
if (( ${#DEVICES[@]} == 0 )); then
  echo "Nenhum aparelho autorizado. Verifique cabo e depuração USB."
  exit 1
fi
if (( ${#DEVICES[@]} > 1 )) && [[ -z "${ANDROID_SERIAL:-}" ]]; then
  echo "Mais de um aparelho conectado (${DEVICES[*]}). Defina ANDROID_SERIAL=<serial> e rode de novo."
  exit 1
fi

PACKAGES=(
  # --- TTS ---
  com.samsung.SMT
  com.samsung.SMT.lang_ru_ru_f00
  com.samsung.SMT.lang_pt_br_f00
  com.samsung.SMT.lang_tr_tr_f00
  com.samsung.SMT.lang_es_mx_f00
  com.samsung.SMT.lang_en_in_l02
  com.samsung.SMT.lang_en_us_f00

  # --- Jogos ---
  com.samsung.android.game.gamehome
  com.samsung.android.game.gametools
  com.samsung.android.game.gos

  # --- Bixby ---
  com.samsung.android.bixby.agent
  com.samsung.android.bixby.wakeup
  com.samsung.android.bixbyvision.framework
  com.samsung.android.visionintelligence
  com.samsung.android.visual.cloudcore

  # --- Serviços e bloatware Samsung ---
  com.samsung.android.app.spage
  com.samsung.sree
  com.samsung.shop
  com.samsung.android.stickercenter
  com.samsung.android.themestore
  com.samsung.android.app.dressroom
  com.samsung.android.app.sharelive
  com.samsung.android.mydevice
  com.samsung.android.app.watchmanager
  com.samsung.android.app.watchmanagerstub
  com.samsung.accessory.budsunitemgr
  com.samsung.android.app.parentalcare
  com.samsung.android.kidsinstaller
  com.samsung.android.widget.pictureframe
  com.samsung.android.app.dofviewer
  com.samsung.android.app.camera.sticker.facearavatar.preload
  com.samsung.android.aremoji
  com.samsung.android.aremojieditor
  com.samsung.android.visualars
  com.samsung.android.service.peoplestripe
  com.samsung.android.app.taskedge
  com.samsung.android.app.clipboardedge
  com.samsung.android.aircommandmanager
  com.samsung.android.sdk.handwriting
  com.samsung.android.hdmapp
  com.samsung.android.smartsuggestions
  com.samsung.android.mapsagent
  com.samsung.android.service.tagservice
  com.samsung.android.beaconmanager
  com.samsung.android.mdx
  com.samsung.android.mdx.kit
  com.samsung.android.photoremasterservice

  # --- Lote extra (risco nulo/baixo) ---
  com.samsung.android.callbgprovider
  com.samsung.android.wallpaper.live
  com.samsung.android.inputshare
  com.samsung.android.allshare.service.mediashare
  com.samsung.android.audiomirroring
  com.samsung.android.motionphoto.app
  com.samsung.android.networkdiagnostic
  com.samsung.android.smartswitchassistant
  com.samsung.android.callassistant
  com.samsung.android.smartmirroring
  com.samsung.android.forest
  com.samsung.android.aware.service

  # --- Telemetria / analytics ---
  com.samsung.android.dqagent
  com.samsung.android.rubin.app
  com.samsung.android.svcagent
  com.samsung.android.knox.analytics.uploader
  com.samsung.android.app.omcagent

  # --- Facebook stubs ---
  com.facebook.services
  com.facebook.appmanager
  com.facebook.system
)

# Mantidos de propósito (NÃO remover): earphonetypec, bluelightfilter,
# singletake.service, dynamiclock, smartcallprovider, gpuwatchapp,
# multisound, knox.securefolder

# Ajustes: "namespace chave valor"
SETTINGS=(
  "secure accessibility_display_daltonizer_enabled 1"
  "secure accessibility_display_daltonizer 0"
  "secure limit_ad_tracking 1"
  "global send_action_app_error 0"
  "global wifi_scan_always_enabled 0"
  "global ble_scan_always_enabled 0"
  "global private_dns_mode hostname"
  "global private_dns_specifier dns.adguard-dns.com"
  "global window_animation_scale 0.5"
  "global transition_animation_scale 0.5"
  "global animator_duration_scale 0.5"
)

RESTRICT=(
  com.linkedin.android
  com.osp.app.signin
  com.shazam.android
)

: > "$LOG"
{
  echo "#!/usr/bin/env bash"
  echo "# Restaura o estado anterior ao debloat de $STAMP"
  echo "# Só desfaz o que este run mudou. Revise antes de executar."
  echo "set -u"
} > "$RESTORE"

INSTALLED="$(adb shell pm list packages --user 0 | tr -d '\r' | sed 's/^package://')"

ok=0; skip=0; fail=0
echo "== Pacotes ==" | tee -a "$LOG"
for pkg in "${PACKAGES[@]}"; do
  if ! grep -qxF "$pkg" <<<"$INSTALLED"; then
    echo "PULOU (não instalado): $pkg" | tee -a "$LOG"; ((skip++)); continue
  fi
  if (( DRY )); then
    echo "REMOVERIA: $pkg" | tee -a "$LOG"; continue
  fi
  out="$(adb shell pm uninstall --user 0 "$pkg" 2>&1 | tr -d '\r')"
  if [[ "$out" == *Success* ]]; then
    echo "REMOVIDO: $pkg" | tee -a "$LOG"
    # %q keeps device-provided names from injecting shell code into the restore script.
    printf 'adb shell cmd package install-existing %q\n' "$pkg" >> "$RESTORE"
    ((ok++))
  else
    echo "FALHOU: $pkg -> $out" | tee -a "$LOG"; ((fail++))
  fi
done

echo | tee -a "$LOG"
echo "== Restrições em segundo plano ==" | tee -a "$LOG"
for pkg in "${RESTRICT[@]}"; do
  if ! grep -qxF "$pkg" <<<"$INSTALLED"; then
    echo "PULOU (não instalado): $pkg" | tee -a "$LOG"; continue
  fi
  if (( DRY )); then
    echo "RESTRINGIRIA: $pkg" | tee -a "$LOG"; continue
  fi
  out="$(adb shell cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND ignore 2>&1 | tr -d '\r')"
  out+="$(adb shell am set-standby-bucket "$pkg" restricted 2>&1 | tr -d '\r')"
  if [[ -n "$out" ]]; then
    echo "FALHOU: $pkg -> $out" | tee -a "$LOG"; ((fail++)); continue
  fi
  echo "RESTRITO: $pkg" | tee -a "$LOG"
  {
    printf 'adb shell cmd appops set %q RUN_ANY_IN_BACKGROUND default\n' "$pkg"
    printf 'adb shell am set-standby-bucket %q active\n' "$pkg"
  } >> "$RESTORE"
done

echo | tee -a "$LOG"
echo "== Ajustes de privacidade ==" | tee -a "$LOG"
for entry in "${SETTINGS[@]}"; do
  read -r ns key val <<<"$entry"
  old="$(adb shell settings get "$ns" "$key" | tr -d '\r')"
  if (( DRY )); then
    echo "AJUSTARIA: $ns $key: $old -> $val" | tee -a "$LOG"; continue
  fi
  adb shell settings put "$ns" "$key" "$val"
  echo "AJUSTADO: $ns $key: $old -> $val" | tee -a "$LOG"
  if [[ "$old" == "null" || -z "$old" ]]; then
    printf 'adb shell settings delete %q %q\n' "$ns" "$key" >> "$RESTORE"
  else
    printf 'adb shell settings put %q %q %q\n' "$ns" "$key" "$old" >> "$RESTORE"
  fi
done

chmod +x "$RESTORE"
echo
echo "Removidos: $ok  Pulados: $skip  Falhas: $fail"
echo "Log: $LOG   Restauração: $RESTORE"
(( DRY )) || echo "Reinicie o celular e teste ligações, câmera, teclado, wifi, NFC e digital."
