#!/usr/bin/env bash
#
# Melepas Panel AHASS dari Raspberry Pi / DietPi.
#
#   sudo bash raspberry/uninstall.sh            # hentikan & hapus unit, data DIPERTAHANKAN
#   sudo bash raspberry/uninstall.sh --purge    # hapus juga /opt/antrianahass dan /var/lib/antrianahass
#
# --purge akan menghapus konfigurasi, unggahan logo, dan password admin.
# Jangan dipakai kalau Anda hanya ingin memperbarui kode (pakai raspberry/install.sh).
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/antrianahass}"
DATA_DIR="${DATA_DIR:-/var/lib/antrianahass}"
PANEL_USER="${PANEL_USER:-ahass}"
LAUNCHER="/usr/local/bin/ahass-kiosk-desktop.sh"
FLAGS_TARGET="/etc/ahass/chromium-flags.conf"

PURGE=0
for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=1 ;;
    -h|--help) awk 'NR>1 && NR<=20 && /^#/ {sub(/^# ?/, ""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Argumen tidak dikenal: $arg" >&2; exit 1 ;;
  esac
done

[ "$(id -u)" = "0" ] || { echo "Jalankan sebagai root: sudo bash raspberry/uninstall.sh" >&2; exit 1; }

echo "[ahass] Menghentikan layanan…"
systemctl disable --now ahass-restart.timer >/dev/null 2>&1 || true
systemctl disable --now ahass-restart.service >/dev/null 2>&1 || true
systemctl disable --now ahass-kiosk.service >/dev/null 2>&1 || true
systemctl disable --now ahass-panel.service >/dev/null 2>&1 || true

echo "[ahass] Menghapus unit & launcher…"
rm -f /etc/systemd/system/ahass-panel.service \
      /etc/systemd/system/ahass-kiosk.service \
      /etc/systemd/system/ahass-restart.service \
      /etc/systemd/system/ahass-restart.timer
rm -rf /etc/systemd/system/ahass-panel.service.d /etc/systemd/system/ahass-kiosk.service.d
rm -f "$LAUNCHER" "$FLAGS_TARGET"
rmdir /etc/ahass 2>/dev/null || true
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

# Matikan Chromium sisa mode desktop.
pkill -f "ahass-kiosk-desktop.sh" 2>/dev/null || true
pkill -f "user-data-dir=.*/\.config/ahass-kiosk" 2>/dev/null || true

echo "[ahass] Membersihkan autostart & tweak…"
for home in /home/* /root; do
  [ -d "$home" ] || continue
  f="$home/.config/lxsession/LXDE/autostart"
  if [ -f "$f" ]; then
    sed -i '\#ahass-kiosk-desktop\.sh#d' "$f"
  fi
  rm -f "$home/.config/autostart/ahass-kiosk.desktop"
done
rm -f /etc/logrotate.d/ahass-kiosk
rm -f /etc/sysctl.d/99-ahass-pi.conf
rm -f /etc/systemd/journald.conf.d/ahass-small.conf
systemctl restart systemd-journald >/dev/null 2>&1 || true

if [ "$PURGE" = "1" ]; then
  echo "[ahass] Menghapus $APP_DIR dan $DATA_DIR (--purge)…"
  rm -rf "$APP_DIR" "$DATA_DIR"
  if id -u "$PANEL_USER" >/dev/null 2>&1; then
    userdel "$PANEL_USER" 2>/dev/null || true
  fi
  echo "[ahass] Selesai. Semua konfigurasi & rahasia telah dihapus."
else
  echo "[ahass] Selesai. Data konfigurasi tetap di $DATA_DIR."
  echo "        Hapus total dengan: sudo bash <repo>/raspberry/uninstall.sh --purge"
fi
