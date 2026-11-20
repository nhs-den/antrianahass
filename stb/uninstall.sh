#!/usr/bin/env bash
#
# Melepas Panel AHASS dari STB Armbian.
#
#   sudo bash stb/uninstall.sh            # hapus unit & layar, data DIPERTAHANKAN
#   sudo bash stb/uninstall.sh --purge    # hapus juga /opt/antrianahass dan /var/lib/antrianahass
#   sudo bash stb/uninstall.sh --keep-fixes  # biarkan xserver-xorg-legacy & Xwrapper
#
# Catatan: skrip ini tidak menghapus paket chromium/nodejs yang sudah terpasang
# karena mungkin dipakai sistem.
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/antrianahass}"
DATA_DIR="${DATA_DIR:-/var/lib/antrianahass}"
PANEL_USER="${PANEL_USER:-ahass}"
PURGE=0
KEEP_FIXES=0

for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=1 ;;
    --keep-fixes) KEEP_FIXES=1 ;;
    -h|--help) awk 'NR>1 && NR<=12 && /^#/ {sub(/^# ?/, ""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Argumen tidak dikenal: $arg" >&2; exit 1 ;;
  esac
done

[ "$(id -u)" = "0" ] || { echo "Jalankan sebagai root: sudo bash stb/uninstall.sh" >&2; exit 1; }

echo "[ahass] Menghentikan layanan…"
systemctl disable --now ahass-restart.timer >/dev/null 2>&1 || true
systemctl disable --now ahass-restart.service >/dev/null 2>&1 || true
systemctl disable --now ahass-kiosk.service >/dev/null 2>&1 || true
systemctl disable --now ahass-panel.service >/dev/null 2>&1 || true

echo "[ahass] Menghapus unit & skrip bantu…"
rm -f /etc/systemd/system/ahass-panel.service \
      /etc/systemd/system/ahass-kiosk.service \
      /etc/systemd/system/ahass-restart.service \
      /etc/systemd/system/ahass-restart.timer \
      /usr/local/bin/ahass-wait-panel.sh
rm -rf /etc/systemd/system/ahass-kiosk.service.d
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

pkill -f "ahass-wait-panel.sh" 2>/dev/null || true
pkill -f "user-data-dir=.*/ahass-kiosk" 2>/dev/null || true
pkill -f "user-data-dir=/var/lib/antrianahass/chromium" 2>/dev/null || true

echo "[ahass] Membersihkan konfigurasi tambahan…"
rm -f /etc/systemd/journald.conf.d/ahass-small.conf
rm -f /etc/sysctl.d/99-ahass-stb.conf
systemctl restart systemd-journald >/dev/null 2>&1 || true

if [ "$KEEP_FIXES" = "0" ]; then
  rm -f /etc/X11/Xwrapper.config
fi
rm -f "$DATA_DIR/.stb-screen-fix" 2>/dev/null || true

if [ "$PURGE" = "1" ]; then
  echo "[ahass] Menghapus $APP_DIR dan $DATA_DIR (--purge)…"
  rm -rf "$APP_DIR" "$DATA_DIR"
  if id -u "$PANEL_USER" >/dev/null 2>&1; then
    userdel "$PANEL_USER" 2>/dev/null || true
  fi
  echo "[ahass] Selesai. Semua konfigurasi & rahasia telah dihapus."
else
  echo "[ahass] Selesai. Data konfigurasi tetap di $DATA_DIR."
  echo "        Hapus total: sudo bash <repo>/stb/uninstall.sh --purge"
fi
