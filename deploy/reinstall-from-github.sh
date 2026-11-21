#!/usr/bin/env bash
#
# Ambil kode TERBARU dari GitHub (repo privat) lalu pasang & restart layanan.
# Dibuat supaya tidak perlu menghafal urutan git clone / gh auth / ZIP lagi.
#
#   sudo bash deploy/reinstall-from-github.sh                 # branch bawaan
#   sudo bash deploy/reinstall-from-github.sh --branch main
#   sudo bash deploy/reinstall-from-github.sh --keep-data     # (bawaan) data tetap
#
# Yang dibutuhkan: `gh` yang sudah login sebagai root (sudo gh auth login),
# ATAU variabel GITHUB_TOKEN, ATAU folder ini sudah berupa repo git.
#
# Data di /var/lib/antrianahass (config, password admin, logo) TIDAK disentuh.
#
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/antrianahass}"
DATA_DIR="${DATA_DIR:-/var/lib/antrianahass}"
REPO="${REPO:-nhs-den/antrianahass}"
BRANCH="${BRANCH:-arena/422be617-antrianahass}"

while [ $# -gt 0 ]; do
  case "$1" in
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --branch=*) BRANCH="${1#*=}"; shift ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --dir) APP_DIR="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Argumen tidak dikenal: $1" >&2; exit 1 ;;
  esac
done

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_info=$'\033[36m'
log()  { echo "${c_info}[ahass]${c_reset} $*"; }
ok()   { echo "${c_ok}[ ok ]${c_reset} $*"; }
warn() { echo "${c_warn}[warn]${c_reset} $*"; }
die()  { echo "${c_err}[fail]${c_reset} $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "Jalankan sebagai root: sudo bash deploy/reinstall-from-github.sh"

# ---------------------------------------------------------------- token/clone
TOKEN=""
if [ -n "${GITHUB_TOKEN:-}" ]; then
  TOKEN="$GITHUB_TOKEN"
elif command -v gh >/dev/null 2>&1; then
  TOKEN="$(gh auth token 2>/dev/null || true)"
fi

clone_with_token() {
  local tmp="$1"
  rm -rf "$tmp"
  if [ -n "$TOKEN" ]; then
    log "Mengambil kode dari GitHub (token gh)…"
    git clone --depth 1 -b "$BRANCH" "https://${TOKEN}@github.com/${REPO}.git" "$tmp"
  else
    log "Mengambil kode dari GitHub (tanpa token, mungkin ditanya password)…"
    git clone --depth 1 -b "$BRANCH" "https://github.com/${REPO}.git" "$tmp" \
      || die "Clone gagal. Login dulu: sudo gh auth login (sekali saja), lalu ulangi."
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -d "$APP_DIR/.git" ]; then
  log "Folder $APP_DIR sudah repo git — memperbarui (fetch + reset ke origin/$BRANCH)…"
  if ! git -C "$APP_DIR" fetch --depth 1 origin "$BRANCH"; then
    clone_with_token "$TMP/src"
    rsync -a --delete --exclude '.git' "$TMP/src/" "$APP_DIR/" 2>/dev/null \
      || cp -a "$TMP/src/." "$APP_DIR/"
  else
    git -C "$APP_DIR" checkout -q -B "$BRANCH" "origin/$BRANCH"
    git -C "$APP_DIR" reset -q --hard "origin/$BRANCH"
  fi
else
  warn "$APP_DIR bukan repo git — mengambil kode baru."
  clone_with_token "$TMP/src"
  mkdir -p "$APP_DIR"
  # salin isi repo ke folder aplikasi (tanpa .git agar tidak setengah-repo)
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude '.git' "$TMP/src/" "$APP_DIR/"
  else
    find "$APP_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    cp -a "$TMP/src/." "$APP_DIR/"
    rm -rf "$APP_DIR/.git"
  fi
fi

# jangan tinggalkan token di konfigurasi git
if [ -f "$APP_DIR/.git/config" ]; then
  sed -i "s#https://[^@/]*@github.com#https://github.com#g" "$APP_DIR/.git/config"
fi

VERSION="$(node -p "require('$APP_DIR/package.json').version" 2>/dev/null || echo '-')"
ok "Kode siap: v$VERSION (branch $BRANCH)."

# ------------------------------------------------------------------- installer
IS_PI=0
[ -r /proc/device-tree/model ] && grep -qi 'raspberry pi' /proc/device-tree/model && IS_PI=1
if [ "$IS_PI" = "1" ] && [ -f "$APP_DIR/raspberry/install.sh" ]; then
  log "Memasang di Raspberry Pi…"
  bash "$APP_DIR/raspberry/install.sh" --no-deps
elif [ -f "$APP_DIR/deploy/install.sh" ]; then
  log "Memasang (deploy/install.sh --no-deps)…"
  # catatan: skrip ini menyalin dari dalam folder yang sama; aman karena
  # sumber dan tujuan identik (tidak menghapus .git milik /opt).
  bash "$APP_DIR/deploy/install.sh" --no-deps || warn "Installer melaporkan masalah; periksa keluarannya."
else
  warn "Installer tidak ditemukan di $APP_DIR."
fi

log "Me-restart layanan…"
systemctl daemon-reload
systemctl restart ahass-panel.service 2>/dev/null || warn "ahass-panel tidak aktif."
systemctl restart ahass-kiosk.service 2>/dev/null || warn "ahass-kiosk tidak aktif (normal bila mode desktop)."

sleep 2
if systemctl is-active --quiet ahass-panel.service; then
  ok "Panel berjalan (v$(node -p "require('$APP_DIR/package.json').version" 2>/dev/null || echo '-'))."
else
  die "Panel gagal berjalan. Periksa: journalctl -u ahass-panel -n 50 --no-pager"
fi

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo
ok "Selesai. Data di $DATA_DIR tetap utuh."
echo "  Panel : http://${IP:-localhost}:8080/"
echo "  Admin : http://${IP:-localhost}:8080/admin"
echo "  Setelah update, buka admin lalu tekan Ctrl+Shift+R sekali."
echo
