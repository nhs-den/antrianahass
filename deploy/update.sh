#!/usr/bin/env bash
#
# Memperbarui Panel AHASS TANPA instalasi ulang.
#
#   sudo bash deploy/update.sh
#
# Yang terjadi:
#   1. (bila folder ini repo git) mengambil kode terbaru: git pull
#   2. menyalin kode ke /opt/antrianahass
#   3. me-restart layanan panel + layar kiosk
#
# Yang TIDAK diubah  : /var/lib/antrianahass (config.json, logo unggahan,
#                      password admin, kunci enkripsi).
# Yang TIDAK dipasang: paket apt (tidak perlu internet/apt saat update).
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${APP_DIR:-/opt/antrianahass}"
DATA_DIR="${DATA_DIR:-/var/lib/antrianahass}"

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_info=$'\033[36m'
log()  { echo "${c_info}[ahass]${c_reset} $*"; }
ok()   { echo "${c_ok}[ ok ]${c_reset} $*"; }
warn() { echo "${c_warn}[warn]${c_reset} $*"; }
die()  { echo "${c_err}[fail]${c_reset} $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "Jalankan sebagai root: sudo bash deploy/update.sh"

OLD_VERSION="$(node -p "require('$APP_DIR/package.json').version" 2>/dev/null || echo '-')"
NEW_VERSION="$(node -p "require('$SRC_DIR/package.json').version" 2>/dev/null || echo '-')"
log "Versi terpasang: $OLD_VERSION → versi baru: $NEW_VERSION"

if [ -d "$SRC_DIR/.git" ]; then
  log "Mengambil kode terbaru…"
  git -C "$SRC_DIR" pull --ff-only || warn "git pull gagal (offline / ada perubahan lokal) — memakai kode yang ada."
else
  warn "Folder sumber bukan repo git; memakai berkas yang ada di $SRC_DIR."
fi

log "Menyalin berkas aplikasi (data tidak disentuh)…"
bash "$SRC_DIR/deploy/install.sh" --no-deps

log "Memuat ulang layar kiosk…"
systemctl restart ahass-kiosk.service 2>/dev/null || warn "Layar kiosk tidak aktif."

sleep 1
if systemctl is-active --quiet ahass-panel.service; then
  ok "Panel berjalan (v$(node -p "require('$APP_DIR/package.json').version"))."
else
  die "Panel gagal berjalan. Periksa: journalctl -u ahass-panel -n 50 --no-pager"
fi

echo
ok "Update selesai. Konfigurasi di $DATA_DIR tetap utuh."
echo "  Panel : http://$(hostname -I 2>/dev/null | awk '{print $1}'):8080/"
echo "  Admin : http://$(hostname -I 2>/dev/null | awk '{print $1}'):8080/admin"
echo
