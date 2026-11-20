#!/usr/bin/env bash
#
# Memastikan layar STB benar-benar menampilkan panel, dengan eskalasi otomatis.
#
#   sudo bash stb/screen-fix.sh              # coba sampai tampil
#   sudo bash stb/screen-fix.sh --no-content # cukup unit+X hidup (tanpa cek piksel)
#   sudo bash stb/screen-fix.sh --reset      # hapus semua drop-in hasil perbaikan
#
# Urutan eskalasi:
#   0. Apa adanya (Chromium sebagai pengguna kiosk, GPU aktif)
#   1. + --disable-gpu            (Mali-450 sering gagal compositing di mainline)
#   2. + xserver-xorg-legacy      (X tidak boleh buka VT sebagai non-root)
#      + layar dijalankan sebagai root (drop-in User=root)
#   3. Menyerah dengan diagnosa lengkap
#
# Berkas status hasil perbaikan: /var/lib/antrianahass/.stb-screen-fix
set -uo pipefail

PORT="${PORT:-8080}"
CHECK_CONTENT=1
RESET=0
UNIT="ahass-kiosk.service"
DROPIN_DIR="/etc/systemd/system/ahass-kiosk.service.d"
FLAGS_FILE="/etc/ahass/chromium-flags.conf"
STATE_FILE="/var/lib/antrianahass/.stb-screen-fix"
XORG_LOG="/var/log/Xorg.0.log"

for arg in "$@"; do
  case "$arg" in
    --port=*) PORT="${arg#*=}" ;;
    --no-content) CHECK_CONTENT=0 ;;
    --reset)
      RESET=1
      ;;
    -h|--help) awk 'NR>1 && NR<=18 && /^#/ {sub(/^# ?/, ""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Argumen tidak dikenal: $arg" >&2; exit 1 ;;
  esac
done

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_info=$'\033[36m'
log()  { echo "${c_info}[layar]${c_reset} $*"; }
ok()   { echo "${c_ok}[ ok ]${c_reset} $*"; }
warn() { echo "${c_warn}[warn]${c_reset} $*"; }
err()  { echo "${c_err}[fail]${c_reset} $*" >&2; }

[ "$(id -u)" = "0" ] || { err "Jalankan sebagai root: sudo bash stb/screen-fix.sh"; exit 1; }

kiosk_user() { systemctl show -p User --value "$UNIT" 2>/dev/null | head -1; }

cleanup_dropins() {
  rm -f "$DROPIN_DIR/stb-nogpu.conf" "$DROPIN_DIR/stb-root.conf" 2>/dev/null
  rmdir "$DROPIN_DIR" 2>/dev/null || true
}

if [ "$RESET" = "1" ]; then
  log "Menghapus drop-in hasil perbaikan…"
  cleanup_dropins
  systemctl daemon-reload
  systemctl restart "$UNIT" 2>/dev/null
  rm -f "$STATE_FILE"
  ok "Reset selesai (kembali ke setelan awal)."
  exit 0
fi

flags_line() {
  [ -r "$FLAGS_FILE" ] || return 1
  sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$FLAGS_FILE" | tr '\n' ' ' | sed 's/  */ /g'
}

unit_running() {
  systemctl is-active --quiet "$UNIT" 2>/dev/null || return 1
  [ "$(systemctl show -p SubState --value "$UNIT" 2>/dev/null)" = "running" ] || return 1
  return 0
}

x_ready() { [ -S /tmp/.X11-unix/X0 ]; }

chromium_alive() {
  pgrep -f "127.0.0.1:${PORT}" >/dev/null 2>&1
}

xauth_file() {
  local u h f
  u="$(kiosk_user)"
  if [ -n "$u" ] && [ "$u" != "root" ]; then
    h="$(getent passwd "$u" | cut -d: -f6)"
    for f in "$h/.Xauthority" "/run/user/$(id -u "$u" 2>/dev/null)/gdm/Xauthority"; do
      [ -s "$f" ] && { echo "$f"; return 0; }
    done
  fi
  for f in /root/.Xauthority /var/lib/lightdm/.Xauthority; do
    [ -s "$f" ] && { echo "$f"; return 0; }
  done
  return 1
}

# 0 = ada isi, 1 = hitam/kosong, 2 = tidak bisa dinilai
screen_has_content() {
  command -v xwd >/dev/null 2>&1 || return 2
  local xa out nonzero
  xa="$(xauth_file)" || xa=""
  # Ambil sebagian saja (2 MB awal tangkapan) agar ringan di STB.
  if [ -n "$xa" ]; then
    out="$(XAUTHORITY="$xa" DISPLAY=:0 timeout 20 xwd -root -silent 2>/dev/null \
      | head -c 2000000 | od -An -tx1 -v 2>/dev/null || true)"
  else
    out="$(DISPLAY=:0 timeout 20 xwd -root -silent 2>/dev/null \
      | head -c 2000000 | od -An -tx1 -v 2>/dev/null || true)"
  fi
  [ -n "$out" ] || return 2
  # Hitung byte yang bukan 0x00; layar hitam hanya menyisakan header xwd.
  nonzero="$(printf '%s' "$out" | awk '{for (i=1;i<=NF;i++) if ($i != "00") n++} END {print n+0}')"
  if [ "${nonzero:-0}" -gt 3000 ]; then
    echo "    (piksel bukan-hitam: $nonzero)"
    return 0
  fi
  echo "    (piksel bukan-hitam hanya $nonzero -> layar tampak gelap)"
  return 1
}

wait_screen() {
  local limit="${1:-30}" i=0
  while [ "$i" -lt "$limit" ]; do
    if unit_running && x_ready && chromium_alive; then
      if [ "$CHECK_CONTENT" = "1" ]; then
        screen_has_content
        case $? in
          0) return 0 ;;
          1) : ;;   # tunggu, mungkin masih memuat
          2) [ "$i" -ge 8 ] && return 0 ;;  # xwd tidak tersedia: cukup unit+X+chromium
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

show_diagnostics() {
  echo
  log "40 baris log ahass-kiosk:"
  journalctl -u "$UNIT" -n 40 --no-pager 2>/dev/null || warn "journal tidak bisa dibaca."
  echo
  if [ -f "$XORG_LOG" ]; then
    log "Baris error Xorg ($XORG_LOG):"
    grep -E "\(EE\)|Fatal|Cannot open|VT" "$XORG_LOG" 2>/dev/null | tail -20 || true
  fi
  echo
  log "Konteks perangkat:"
  echo "    uname   : $(uname -a)"
  echo "     DRI    : $(ls /dev/dri 2>/dev/null | tr '\n' ' ' || echo 'tidak ada')"
  echo "     fb     : $(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || echo 'tidak ada')"
  echo "     panel  : $(curl -fs -m 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/__ahass/api/health" 2>/dev/null || echo 'tidak menjawab')"
  echo
  echo "Kirim keluaran di atas untuk analisis. Saran cepat:"
  echo "  - Coba resolusi lebih rendah: sudo bash $0 --reset && sudo bash /opt/antrianahass/stb/install.sh --resolution=1280x720 --no-deps"
  echo "  - Kalau /dev/dri kosong, GPU tidak aktif: --disable-gpu (dicoba otomatis pada langkah 1)."
  echo "  - Periksa DTB di /boot/uEnv.txt (armbianEnv.txt) sesuai model box."
}

attempt() {
  local label="$1"
  log "Mencoba: $label"
  systemctl daemon-reload
  systemctl restart "$UNIT" 2>/dev/null || true
  if wait_screen 35; then
    return 0
  fi
  warn "Belum tampil pada langkah ini."
  return 1
}

echo
log "Memeriksa kondisi awal…"
if ! systemctl list-unit-files 2>/dev/null | grep -q "^${UNIT}"; then
  err "Unit $UNIT belum terpasang. Jalankan dulu: sudo bash stb/install.sh --no-deps"
  exit 1
fi
if ! curl -fs -m 2 -o /dev/null "http://127.0.0.1:${PORT}/__ahass/api/health" 2>/dev/null; then
  warn "Panel belum menjawab di port ${PORT}; layar akan tetap dicoba tetapi kemungkinan kosong."
fi

# Mulai dari keadaan bersih supaya hasil langkah sebelumnya tidak menumpuk.
cleanup_dropins

# ---------------------------------------------------------------- langkah 0
if attempt "apa adanya (GPU aktif, pengguna $(kiosk_user))"; then
  ok "Layar menampilkan panel tanpa perubahan tambahan."
  echo "langsung $(date '+%F %T')" > "$STATE_FILE" 2>/dev/null || true
  exit 0
fi

# ---------------------------------------------------------------- langkah 1
BASE_FLAGS="$(flags_line)" || BASE_FLAGS=""
mkdir -p "$DROPIN_DIR"
cat > "$DROPIN_DIR/stb-nogpu.conf" <<EOF
# Ditambahkan oleh stb/screen-fix.sh: paksa rendering software (Mali-450/mainline)
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
# Diatur oleh stb/screen-fix.sh (Panel AHASS)
allowed_users=anybody
needs_root_rights=yes
EOF

cat > "$DROPIN_DIR/stb-root.conf" <<'EOF'
# Ditambahkan oleh stb/screen-fix.sh: Xorg butuh VT, jadi layar dijalankan sebagai root.
# start-kiosk.sh menambahkan --no-sandbox otomatis ketika berjalan sebagai root.
[Service]
User=root
Group=root
PAMName=
Environment=HOME=/root
EOF

if attempt "layar sebagai root + xserver-xorg-legacy"; then
  ok "Layar tampil (mode root)."
  echo "root $(date '+%F %T')" > "$STATE_FILE" 2>/dev/null || true
  echo
  warn "Layar berjalan sebagai root. Untuk kembali ke mode terbatas:"
  warn "  sudo bash /opt/antrianahass/stb/screen-fix.sh --reset"
  exit 0
fi

# ---------------------------------------------------------------- langkah 3
err "Layar belum bisa menampilkan panel setelah 3 langkah."
show_diagnostics
echo "gagal $(date '+%F %T')" > "$STATE_FILE" 2>/dev/null || true
exit 1
