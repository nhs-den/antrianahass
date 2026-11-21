#!/usr/bin/env bash
#
# Perbaiki layar kiosk Raspberry Pi secara bertahap, dengan verifikasi nyata
# (bukan hanya "unit aktif").
#
#   sudo bash raspberry/screen-fix.sh            # uji + perbaiki sampai tampil
#   sudo bash raspberry/screen-fix.sh --reset    # cabut semua perbaikan
#   sudo bash raspberry/screen-fix.sh --no-content   # tanpa uji piksel (xwd)
#   sudo bash raspberry/screen-fix.sh --diagnose # hanya laporkan, tidak mengubah
#
# Yang diperiksa untuk menyatakan "berhasil":
#   1. unit ahass-kiosk running
#   2. socket X (/tmp/.X11-unix/X0) ada
#   3. proses Chromium menampilkan URL panel
#   4. isi layar benar-benar berwarna (dibaca lewat xwd; layar hitam gagal)
#
# Eskalasi:
#   0) apa adanya
#   1) + --disable-gpu              (GPU/driver bermasalah)
#   2) Xorg legacy + layar sebagai root (TTY tidak bisa dibuka non-root)
#   3) diagnosa lengkap
set -uo pipefail

APP_DIR="${APP_DIR:-/opt/antrianahass}"
DATA_DIR="${DATA_DIR:-/var/lib/antrianahass}"
PORT="${PORT:-8080}"
UNIT="ahass-kiosk.service"
DROPIN_DIR="/etc/systemd/system/ahass-kiosk.service.d"
FLAGS_FILE="/etc/ahass/chromium-flags.conf"
STATE_FILE="/var/lib/antrianahass/.screen-fix"
XORG_LOG_HINT="/home/"
CHECK_CONTENT=1
MODE="fix"

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_info=$'\033[36m'
log()  { echo "${c_info}[layar]${c_reset} $*"; }
ok()   { echo "${c_ok}[ ok ]${c_reset} $*"; }
warn() { echo "${c_warn}[warn]${c_reset} $*"; }
err()  { echo "${c_err}[fail]${c_reset} $*"; }

for arg in "$@"; do
  case "$arg" in
    --reset) MODE="reset" ;;
    --no-content) CHECK_CONTENT=0 ;;
    --diagnose) MODE="diagnose" ;;
    -h|--help) awk 'NR>1 && NR<=16 && /^#/ {sub(/^# ?/, ""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Argumen tidak dikenal: $arg" >&2; exit 1 ;;
  esac
done

flags_line() {
  [ -r "$FLAGS_FILE" ] || return 1
  sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$FLAGS_FILE" | tr '\n' ' ' | sed 's/  */ /g'
}

kiosk_user() { systemctl show -p User --value "$UNIT" 2>/dev/null | head -1; }

unit_running() {
  systemctl is-active --quiet "$UNIT" 2>/dev/null || return 1
  [ "$(systemctl show -p SubState --value "$UNIT" 2>/dev/null)" = "running" ] || return 1
}

x_ready() { [ -S /tmp/.X11-unix/X0 ]; }

chromium_alive() {
  pgrep -f "user-data-dir=.*ahass" >/dev/null 2>&1 && return 0
  pgrep -f "127.0.0.1:${PORT}" >/dev/null 2>&1
}

xauth_file() {
  local u h f
  u="$(kiosk_user)"
  if [ -n "$u" ] && [ "$u" != "root" ]; then
    h="$(getent passwd "$u" | cut -d: -f6)"
    for f in "$h/.Xauthority"; do [ -s "$f" ] && { echo "$f"; return 0; }; done
  fi
  for f in /root/.Xauthority; do [ -s "$f" ] && { echo "$f"; return 0; }; done
  return 1
}

xorg_log() {
  local u h
  u="$(kiosk_user)"
  if [ -n "$u" ] && [ "$u" != "root" ]; then
    h="$(getent passwd "$u" | cut -d: -f6)"
    [ -r "$h/.local/share/xorg/Xorg.0.log" ] && { echo "$h/.local/share/xorg/Xorg.0.log"; return 0; }
  fi
  [ -r /var/lib/xorg/Xorg.0.log ] && { echo /var/lib/xorg/Xorg.0.log; return 0; }
  return 1
}

# 0 = ada isi, 1 = gelap/kosong, 2 = tidak bisa dinilai
screen_has_content() {
  command -v xwd >/dev/null 2>&1 || return 2
  local xa out nonzero
  xa="$(xauth_file)" || xa=""
  # Ambil sebagian saja (2 MB awal) agar ringan di Pi.
  if [ -n "$xa" ]; then
    out="$(XAUTHORITY="$xa" DISPLAY=:0 timeout 20 xwd -root -silent 2>/dev/null \
      | head -c 2000000 | od -An -tx1 -v 2>/dev/null || true)"
  else
    out="$(DISPLAY=:0 timeout 20 xwd -root -silent 2>/dev/null \
      | head -c 2000000 | od -An -tx1 -v 2>/dev/null || true)"
  fi
  [ -n "$out" ] || return 2
  nonzero="$(printf '%s' "$out" | awk '{for (i=1;i<=NF;i++) if ($i != "00") n++} END {print n+0}')"
  if [ "${nonzero:-0}" -gt 3000 ]; then
    echo "    (piksel bukan-hitam: $nonzero)"
    return 0
  fi
  echo "    (piksel bukan-hitam hanya $nonzero -> layar gelap)"
  return 1
}

panel_ok() {
  command -v curl >/dev/null 2>&1 || return 0
  curl -fs -m 4 -o /dev/null "http://127.0.0.1:${PORT}/__ahass/api/health" 2>/dev/null
}

wait_screen() {
  local limit="${1:-40}" i=0
  while [ "$i" -lt "$limit" ]; do
    if unit_running && x_ready && chromium_alive; then
      if [ "$CHECK_CONTENT" = "1" ]; then
        screen_has_content
        case $? in
          0) return 0 ;;
          1) : ;;
          2) [ "$i" -ge 10 ] && return 0 ;;
        esac
      else
        return 0
      fi
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

cleanup_dropins() {
  if [ -d "$DROPIN_DIR" ]; then
    # Hanya drop-in milik skrip ini; drop-in lain (mis. 10-profile.conf) dibiarkan.
    rm -f "$DROPIN_DIR/pi-nogpu.conf" "$DROPIN_DIR/pi-root.conf"
  fi
  systemctl daemon-reload 2>/dev/null || true
}

show_diagnostics() {
  local xl
  echo
  if panel_ok; then ok "Panel menjawab di http://127.0.0.1:${PORT}/"; else
    err "Panel TIDAK menjawab — ini penyebab paling sering layar kosong."
    echo "    Periksa: systemctl status ahass-panel --no-pager"
    echo "             journalctl -u ahass-panel -n 30 --no-pager"
  fi

  log "40 baris log ${UNIT}:"
  journalctl -u "$UNIT" -n 40 --no-pager 2>/dev/null || warn "journal tidak bisa dibaca."

  xl="$(xorg_log)" || xl=""
  if [ -n "$xl" ]; then
    echo
    log "Baris penting Xorg ($xl):"
    grep -E "\(EE\)|Fatal|no screens|Permission denied|fb0|modesetting|fbdev" "$xl" 2>/dev/null | tail -12 || true
  fi

  echo
  log "Konteks perangkat:"
  echo "    model   : $(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo '?')"
  echo "    fb      : $(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || echo 'tidak ada')"
  echo "    /dev/fb0: $(ls -l /dev/fb0 2>/dev/null | awk '{print $1, $3, $4}' || echo 'tidak ada')"
  echo "    /dev/dri: $(ls /dev/dri 2>/dev/null | tr '\n' ' ' || echo 'tidak ada')"
  echo "    grup    : $(systemctl show -p SupplementaryGroups --value "$UNIT" 2>/dev/null || echo '?')"
  echo
  echo "Saran cepat:"
  echo "  - Tepi terpotong / gambar kecil  : atur Resolusi di halaman admin (Tampilan)."
  echo "  - Layar hitam, unit aktif        : sudo bash $0 (eskalasi otomatis)."
  echo "  - fb0 Permission denied          : drop-in SupplementaryGroups=video (lihat README)."
}

attempt() {
  log "Mencoba: $1"
  systemctl daemon-reload
  systemctl restart "$UNIT" 2>/dev/null || true
  wait_screen 40
}

# ---------------------------------------------------------------- reset
if [ "$MODE" = "reset" ]; then
  cleanup_dropins
  if [ -f /etc/X11/Xwrapper.config ] && grep -q "Panel AHASS" /etc/X11/Xwrapper.config 2>/dev/null; then
    rm -f /etc/X11/Xwrapper.config
  fi
  rm -f "$STATE_FILE"
  ok "Reset selesai (kembali ke setelan awal)."
  systemctl restart "$UNIT" 2>/dev/null || true
  exit 0
fi

# ------------------------------------------------------------- diagnose
if [ "$MODE" = "diagnose" ]; then
  log "Diagnosa tanpa mengubah apa pun."
  unit_running && ok "unit running" || err "unit tidak running"
  x_ready && ok "socket X ada" || err "socket X tidak ada"
  chromium_alive && ok "proses Chromium ada" || err "Chromium tidak ditemukan"
  [ "$CHECK_CONTENT" = "1" ] && { screen_has_content || true; }
  show_diagnostics
  exit 0
fi

# ------------------------------------------------------------------- fix
[ "$(id -u)" = "0" ] || { err "Jalankan sebagai root: sudo bash $0"; exit 1; }

echo
log "Memeriksa kondisi awal…"
if ! systemctl list-unit-files 2>/dev/null | grep -q "^${UNIT}"; then
  err "Unit $UNIT belum terpasang. Jalankan dulu: sudo bash $APP_DIR/raspberry/install.sh --no-deps"
  exit 1
fi

if ! panel_ok; then
  warn "Panel belum menjawab; layar tetap dicoba, tetapi kemungkinan kosong."
fi

cleanup_dropins

# ---------------------------------------------------------------- langkah 0
if attempt "apa adanya (pengguna $(kiosk_user))"; then
  ok "Layar menampilkan panel tanpa perubahan tambahan."
  echo "langsung $(date '+%F %T')" > "$STATE_FILE" 2>/dev/null || true
  exit 0
fi

# ---------------------------------------------------------------- langkah 1
BASE_FLAGS="$(flags_line)" || BASE_FLAGS=""
mkdir -p "$DROPIN_DIR"
cat > "$DROPIN_DIR/pi-nogpu.conf" <<EOF
# Ditambahkan raspberry/screen-fix.sh: rendering software (GPU Pi bermasalah)
[Service]
Environment="CHROMIUM_FLAGS=$BASE_FLAGS --disable-gpu"
EOF
if attempt "rendering software (--disable-gpu)"; then
  ok "Layar tampil dengan --disable-gpu."
  echo "nogpu $(date '+%F %T')" > "$STATE_FILE" 2>/dev/null || true
  exit 0
fi

# ---------------------------------------------------------------- langkah 2
log "Memasang xserver-xorg-legacy dan menjalankan layar sebagai root…"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends xserver-xorg-legacy >/dev/null 2>&1 \
  || warn "xserver-xorg-legacy gagal dipasang (mungkin sudah ada)."

cat > /etc/X11/Xwrapper.config <<'EOF'
# Diatur oleh raspberry/screen-fix.sh (Panel AHASS)
allowed_users=anybody
needs_root_rights=yes
EOF

cat > "$DROPIN_DIR/pi-root.conf" <<'EOF'
# Ditambahkan raspberry/screen-fix.sh: Xorg butuh VT, jadi layar dijalankan sebagai root.
# deploy/start-kiosk.sh menambahkan --no-sandbox otomatis saat berjalan sebagai root.
[Service]
User=root
Group=root
PAMName=
Environment=HOME=/root
Environment=AHASS_PROFILE_DIR=/root/.config/ahass-kiosk
EOF
mkdir -p /root/.config/ahass-kiosk 2>/dev/null || true

if attempt "layar sebagai root + xserver-xorg-legacy"; then
  ok "Layar tampil (mode root)."
  echo "root $(date '+%F %T')" > "$STATE_FILE" 2>/dev/null || true
  echo
  warn "Layar berjalan sebagai root. Untuk kembali ke mode terbatas:"
  warn "  sudo bash $0 --reset"
  exit 0
fi

# ---------------------------------------------------------------- langkah 3
err "Layar belum bisa menampilkan panel setelah 3 langkah."
show_diagnostics
echo "gagal $(date '+%F %T')" > "$STATE_FILE" 2>/dev/null || true
exit 1
