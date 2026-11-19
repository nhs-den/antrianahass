#!/usr/bin/env bash
#
# Melepas layanan Panel AHASS (data konfigurasi tetap disimpan).
#
#   sudo bash deploy/uninstall.sh           # lepas layanan, simpan data
#   sudo bash deploy/uninstall.sh --purge   # hapus juga aplikasi & data
#
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/antrianahass}"
DATA_DIR="${DATA_DIR:-/var/lib/antrianahass}"
PURGE=0

for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=1 ;;
  esac
done

if [ "$(id -u)" != "0" ]; then
  echo "Jalankan sebagai root: sudo bash deploy/uninstall.sh" >&2
  exit 1
fi

echo "[ahass] Menghentikan layanan…"
systemctl disable --now ahass-kiosk.service 2>/dev/null || true
systemctl disable --now ahass-panel.service 2>/dev/null || true
systemctl disable --now ahass-restart.timer 2>/dev/null || true

rm -f /etc/systemd/system/ahass-panel.service \
      /etc/systemd/system/ahass-kiosk.service \
      /etc/systemd/system/ahass-restart.service \
      /etc/systemd/system/ahass-restart.timer
systemctl daemon-reload

if [ "$PURGE" = "1" ]; then
  echo "[ahass] Menghapus aplikasi dan data…"
  rm -rf "$APP_DIR" "$DATA_DIR"
  userdel ahass 2>/dev/null || true
  userdel -r kiosk 2>/dev/null || true
  echo "[ahass] Selesai (aplikasi + data dihapus)."
else
  echo "[ahass] Layanan dilepas. Aplikasi di $APP_DIR dan data di $DATA_DIR dibiarkan."
fi
