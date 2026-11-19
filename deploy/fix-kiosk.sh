#!/usr/bin/env bash
#
# Mendiagnosis dan memperbaiki layar kiosk (ahass-kiosk.service) yang gagal start.
#
#   sudo bash deploy/fix-kiosk.sh
#   sudo bash deploy/fix-kiosk.sh --dry-run
#   sudo bash deploy/fix-kiosk.sh --user     # paksa mode non-root (default: otomatis)
#
# Penyebab paling umum:
#   1. paket chromium / xinit / xauth belum terpasang  → dipasang otomatis
#   2. Xorg tidak boleh membuka /dev/tty sebagai user biasa → dipasang
#      xserver-xorg-legacy + unit dijalankan sebagai root (drop-in)
#   3. desktop (LXDE/lightdm) ikut memakai tty1 → diberi peringatan
#
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/antrianahass}"
KIOSK_USER="${KIOSK_USER:-kiosk}"
MODE="auto"
DRY_RUN=0
DROPIN_DIR=/etc/systemd/system/ahass-kiosk.service.d

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --user) MODE="user"; shift ;;
    --root) MODE="root"; shift ;;
    -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Argumen tidak dikenal: $1" >&2; exit 1 ;;
  esac
done

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_info=$'\033[36m'
log()  { echo "${c_info}[kiosk]${c_reset} $*"; }
ok()   { echo "${c_ok}[ ok ]${c_reset} $*"; }
warn() { echo "${c_warn}[warn]${c_reset} $*"; }
die()  { echo "${c_err}[fail]${c_reset} $*" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = "1" ]; then echo "    (dry-run) $*"; else "$@"; fi; }

[ "$(id -u)" = "0" ] || die "Jalankan sebagai root: sudo bash deploy/fix-kiosk.sh"

echo
log "Pemeriksaan awal"
[ -x "$APP_DIR/deploy/start-kiosk.sh" ] || die "Tidak ditemukan $APP_DIR/deploy/start-kiosk.sh — jalankan deploy/install.sh dulu."
ok "start-kiosk.sh ada"

for unit in lightdm gdm3 sddm lxdm; do
  if systemctl is-active --quiet "$unit" 2>/dev/null; then
    warn "Display manager '$unit' aktif dan mungkin memakai tty1."
    warn "Matikan desktop otomatis DietPi: jalankan 'dietpi-autostart' → pilih Manual/Console, lalu reboot."
  fi
done
[ -e /dev/dri/card0 ] && ok "GPU/DRM terdeteksi (/dev/dri/card0)" || warn "Tidak ada /dev/dri/card0 — Xorg akan memakai mode software."

# ------------------------------------------------------------- 1. paket
MISSING=""
for pkg in chromium xinit xauth xserver-xorg x11-xserver-utils unclutter fonts-dejavu-core ca-certificates; do
  dpkg -s "$pkg" >/dev/null 2>&1 || MISSING="$MISSING $pkg"
done

if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1 && [[ "$MISSING" != *" chromium"* ]]; then
  MISSING="$MISSING chromium"
fi

if [ -n "$MISSING" ]; then
  warn "Paket belum terpasang:$MISSING"
  log "Memasang paket yang kurang…"
  if [ "$DRY_RUN" = "1" ]; then
    echo "    (dry-run) apt-get update && apt-get install -y$MISSING"
  else
    apt-get update -qq || warn "apt-get update gagal, mencoba dengan cache lama."
    # shellcheck disable=SC2086
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $MISSING; then
      warn "Sebagian paket gagal dipasang."
      if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
        log "Mencoba pemasang paket DietPi (dietpi-software 113 = Chromium)…"
        run dietpi-software install 113 || warn "dietpi-software tidak tersedia/gagal."
      fi
    fi
  fi
else
  ok "Semua paket pendukung sudah terpasang"
fi

CHROME=""
for candidate in chromium chromium-browser google-chrome google-chrome-stable; do
  command -v "$candidate" >/dev/null 2>&1 && { CHROME="$(command -v "$candidate")"; break; }
done
[ -n "$CHROME" ] && ok "Browser: $CHROME" || warn "Browser belum ditemukan — layar tidak akan bisa tampil sebelum chromium terpasang."

run chmod +x "$APP_DIR/deploy/start-kiosk.sh" || true

# --------------------------------------------------- 2. uji unit apa adanya
try_start() {
  systemctl daemon-reload
  systemctl restart ahass-kiosk.service 2>/dev/null || true
  local i=0
  while [ $i -lt 8 ]; do
    sleep 1
    if systemctl is-active --quiet ahass-kiosk.service; then
      # masih "activating"? pastikan benar-benar running
      local state
      state="$(systemctl show -p SubState --value ahass-kiosk.service || echo '')"
      [ "$state" = "running" ] && return 0
    fi
    i=$((i + 1))
  done
  return 1
}

echo
log "Menjalankan ulang layar kiosk (mode: $( [ "$MODE" = "root" ] && echo root || echo "user $KIOSK_USER" ))…"
if [ "$DRY_RUN" = "1" ]; then
  echo "    (dry-run) systemctl restart ahass-kiosk"
  exit 0
fi

if [ -n "$CHROME" ] && try_start; then
  ok "Layar kiosk berjalan."
  MODE_DONE="user"
else
  if [ -z "$CHROME" ]; then
    die "Chromium tidak tersedia. Pasang dulu: apt-get install -y chromium"
  fi

  warn "Gagal pada mode non-root. 15 baris log terakhir:"
  journalctl -u ahass-kiosk -n 15 --no-pager 2>/dev/null || true

  log "Memasang xserver-xorg-legacy + menjalankan layar sebagai root (drop-in)…"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends xserver-xorg-legacy >/dev/null 2>&1 || warn "xserver-xorg-legacy gagal dipasang."

  cat > /etc/X11/Xwrapper.config <<'EOF'
# Diatur oleh deploy/fix-kiosk.sh (Panel AHASS)
allowed_users=anybody
needs_root_rights=yes
EOF

  mkdir -p "$DROPIN_DIR"
  cat > "$DROPIN_DIR/root.conf" <<'EOF'
# Kiosk AHASS berjalan sebagai root agar Xorg dapat membuka VT (/dev/tty1)
[Service]
User=root
Group=root
PAMName=
EOF

  if try_start; then
    ok "Layar kiosk berjalan (mode root)."
    MODE_DONE="root"
  else
    warn "Masih gagal. 25 baris log terakhir:"
    journalctl -u ahass-kiosk -n 25 --no-pager 2>/dev/null || true
    if [ -f /var/log/Xorg.0.log ]; then
      echo
      log "Baris error dari /var/log/Xorg.0.log:"
      grep -E "\(EE\)|Fatal|Cannot open" /var/log/Xorg.0.log | tail -15 || true
    fi
    die "Layar belum bisa tampil. Kirimkan keluaran di atas untuk analisis lanjutan."
  fi
fi

# ------------------------------------------------------------- 3. ringkas
echo
ok "Selesai (mode: ${MODE_DONE:-user})."
echo "  Panel  : http://localhost:8080/"
echo "  Cek    : systemctl status ahass-kiosk --no-pager"
echo "  Log    : journalctl -u ahass-kiosk -f"
if [ "${MODE_DONE:-user}" = "root" ]; then
  echo
  warn "Layar berjalan sebagai root. Untuk kembali ke mode terbatas:"
  warn "  sudo rm -rf $DROPIN_DIR && sudo systemctl restart ahass-kiosk"
fi
echo
