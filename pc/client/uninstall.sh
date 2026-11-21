#!/usr/bin/env bash
#
# Lepas layar STB-client (STB kembali jadi perangkat biasa, tanpa kiosk).
#
#   sudo bash pc/client/uninstall.sh              # lepas layar + Xwrapper
#   sudo bash pc/client/uninstall.sh --keep-fixes # biarkan Xwrapper/xserver-legacy
#   sudo bash pc/client/uninstall.sh --purge      # hapus juga profil & berkas /etc
#
# Server di PC TIDAK tersentuh - ini hanya sisi STB.
set -uo pipefail

KEEP_FIXES=0
PURGE=0
for arg in "$@"; do
  case "$arg" in
    --keep-fixes) KEEP_FIXES=1 ;;
    --purge) PURGE=1 ;;
    -h|--help) awk 'NR>1 && NR<=9 && /^#/ {sub(/^# ?/, ""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Argumen tidak dikenal: $arg" >&2; exit 1 ;;
  esac
done

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_info=$'\033[36m'
log()  { echo "${c_info}[stb]${c_reset} $*"; }
ok()   { echo "${c_ok}[ ok ]${c_reset} $*"; }
warn() { echo "${c_warn}[warn]${c_reset} $*"; }
die()  { echo "${c_err}[fail]${c_reset} $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "Jalankan sebagai root: sudo bash pc/client/uninstall.sh"

log "Menghentikan layar…"
systemctl disable --now ahass-pc-kiosk.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/ahass-pc-kiosk.service
rm -rf /etc/systemd/system/ahass-pc-kiosk.service.d
systemctl daemon-reload 2>/dev/null || true
ok "Unit ahass-pc-kiosk dilepas."

rm -f /usr/local/bin/ahass-pc-kiosk.sh /usr/local/bin/ahass-pc-wait-panel.sh \
      /usr/local/bin/ahass-pc-screen-fix.sh
ok "Skrip layar dihapus."

if [ "$KEEP_FIXES" = "0" ]; then
  if [ -f /etc/X11/Xwrapper.config ] && grep -q "Panel AHASS" /etc/X11/Xwrapper.config 2>/dev/null; then
    rm -f /etc/X11/Xwrapper.config
    ok "Xwrapper.config (dibuat screen-fix) dihapus."
  fi
else
  warn "--keep-fixes: Xwrapper.config dibiarkan."
fi

if [ "$PURGE" = "1" ]; then
  rm -rf /var/lib/antrianahass-client /etc/ahass-client
  ok "Profil Chromium & konfigurasi client dihapus (--purge)."
else
  log "Profil & konfigurasi dipertahankan di /var/lib/antrianahass-client dan /etc/ahass-client."
fi

log "Mengaktifkan kembali konsol tty1…"
systemctl enable getty@tty1.service >/dev/null 2>&1 || true

echo
ok "STB-client dilepas. Server di PC tidak berubah."
echo "  Pasang lagi: sudo bash pc/client/install.sh --pc=IP-PC"
