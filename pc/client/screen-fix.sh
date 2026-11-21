#!/usr/bin/env bash
#
# Perbaiki layar STB-client (menampilkan panel dari PC) secara bertahap.
#
#   sudo bash pc/client/screen-fix.sh              # uji & perbaiki sampai tampil
#   sudo bash pc/client/screen-fix.sh --reset      # cabut semua perbaikan
#   sudo bash pc/client/screen-fix.sh --no-content # cukup unit+X+Chromium (tanpa xwd)
#
# Eskalasi:
#   0) apa adanya (Chromium sebagai pengguna kiosk)
#   1) + --disable-gpu             (Mali-450 / driver mainline bermasalah)
#   2) Xorg legacy + layar sebagai root (Xorg tidak boleh buka VT sebagai non-root)
#   3) diagnosa + saran
#
# Berbeda dari stb/screen-fix.sh: di sini kesehatan PANEL DI PC juga diperiksa,
# karena layar kosong sering disebabkan jaringan, bukan GPU.
set -uo pipefail

UNIT="ahass-pc-kiosk.service"
DROPIN_DIR="/etc/systemd/system/ahass-pc-kiosk.service.d"
FLAGS_FILE="/etc/ahass-client/chromium-flags.conf"
URL_FILE="/etc/ahass-client/panel-url"
STATE_FILE="/var/lib/antrianahass-client/.screen-fix"
XORG_LOG="/var/log/Xorg.0.log"
CHECK_CONTENT=1
RESET=0

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_info=$'\033[36m'
log()  { echo "${c_info}[layar]${c_reset} $*"; }
ok()   { echo "${c_ok}[ ok ]${c_reset} $*"; }
warn() { echo "${c_warn}[warn]${c_reset} $*"; }
err()  { echo "${c_err}[fail]${c_reset} $*"; }

for arg in "$@"; do
  case "$arg" in
    --reset) RESET=1 ;;
    --no-content) CHECK_CONTENT=0 ;;
    -h|--help) awk 'NR>1 && NR<=12 && /^#/ {sub(/^# ?/, ""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Argumen tidak dikenal: $arg" >&2; exit 1 ;;
  esac
done

panel_url() {
  if [ -r "$URL_FILE" ]; then head -1 "$URL_FILE"; else echo "http://127.0.0.1:8080/"; fi
}

cleanup_dropins() {
  if [ -d "$DROPIN_DIR" ]; then
    rm -f "$DROPIN_DIR/client-nogpu.conf" "$DROPIN_DIR/client-root.conf"
    rmdir "$DROPIN_DIR" 2>/dev/null || true
  fi
  systemctl daemon-reload 2>/dev/null || true
}

if [ "$RESET" = "1" ]; then
  cleanup_dropins
  if [ -f /etc/X11/Xwrapper.config ] && grep -q "Panel AHASS" /etc/X11/Xwrapper.config 2>/dev/null; then
    rm -f /etc/X11/Xwrapper.config
  fi
  rm -f "$STATE_FILE"
  ok "Reset selesai (kembali ke setelan awal)."
  exit 0
fi

[ "$(id -u)" = "0" ] || { err "Jalankan sebagai root: sudo bash pc/client/screen-fix.sh"; exit 1; }

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
  local host
  host="$(panel_url | sed -e 's#^https\?://##' -e 's#[:/].*##')"
  [ -n "$host" ] && pgrep -f "$host" >/dev/null 2>&1 && return 0
  pgrep -f "ahass-pc-kiosk.sh" >/dev/null 2>&1 && return 0
  pgrep -f "user-data-dir=.*ahass-kiosk" >/dev/null 2>&1
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

# 0 = ada isi, 1 = gelap, 2 = tidak bisa dinilai
screen_has_content() {
  command -v xwd >/dev/null 2>&1 || return 2
  local xa out nonzero
  xa="$(xauth_file)" || xa=""
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

panel_reachable() {
  local u; u="$(panel_url)"; u="${u%/}"
  command -v curl >/dev/null 2>&1 || return 0
  curl -fs -m 5 -o /dev/null "${u}/__ahass/api/health" 2>/dev/null
}

wait_screen() {
  local limit="${1:-35}" i=0
  while [ "$i" -lt "$limit" ]; do
    if unit_running && x_ready && chromium_alive; then
      if [ "$CHECK_CONTENT" = "1" ]; then
        screen_has_content
        case $? in
          0) return 0 ;;
          1) : ;;
          2) [ "$i" -ge 8 ] && return 0 ;;
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

attempt() {
  log "Mencoba: $1"
  systemctl daemon-reload
  systemctl restart "$UNIT" 2>/dev/null || true
  wait_screen 35
}

show_diagnostics() {
  local u; u="$(panel_url)"
  echo
  log "Alamat panel: $u"
  if panel_reachable; then
    ok "PC menjawab dari STB."
  else
    err "PC TIDAK menjawab dari STB -> ini penyebab paling mungkin, bukan GPU."
    echo "    Cek di PC : systemctl status ahass-pc   /   Service 'AhassPanel' (Windows)"
    echo "    Cek di STB: ping $(echo "$u" | sed -e 's#http://##' -e 's#[:/].*##')"
    echo "    Buka port : ufw allow $(echo "$u" | sed -e 's#.*:##' -e 's#/.*##')/tcp"
    echo "    IP berubah: sudo bash pc/client/install.sh --pc=IP-PC-BARU"
    echo
  fi
  log "40 baris log $UNIT:"
  journalctl -u "$UNIT" -n 40 --no-pager 2>/dev/null || warn "journal tidak bisa dibaca."
  if [ -f "$XORG_LOG" ]; then
    echo
    log "Baris error Xorg:"
    grep -E "\(EE\)|Fatal|Cannot open|VT" "$XORG_LOG" 2>/dev/null | tail -15 || true
  fi
  echo
  log "Konteks perangkat:"
  echo "    uname : $(uname -a)"
  echo "     DRI   : $(ls /dev/dri 2>/dev/null | tr '\n' ' ' || echo 'tidak ada')"
  echo "     fb    : $(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || echo 'tidak ada')"
}

echo
log "Memeriksa kondisi awal…"
if ! systemctl list-unit-files 2>/dev/null | grep -q "^${UNIT}"; then
  err "Unit $UNIT belum terpasang. Jalankan dulu:"
  err "  sudo bash pc/client/install.sh --pc=IP-PC"
  exit 1
fi

if ! panel_reachable; then
  warn "PC belum menjawab di $(panel_url) — layar akan tetap diuji, tapi kemungkinan kosong."
fi

# Kalau kiosk mode mandiri (stb/) masih ada dan aktif, dua unit akan berebut
# tty1/X. Installer mematikannya; di sini diperiksa ulang.
for other in ahass-kiosk.service; do
  if systemctl is-enabled --quiet "$other" 2>/dev/null; then
    warn "$other masih enabled dan akan berebut tty1 - dimatikan."
    systemctl disable --now "$other" >/dev/null 2>&1 || true
  fi
done

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
cat > "$DROPIN_DIR/client-nogpu.conf" <<EOF
# Ditambahkan pc/client/screen-fix.sh: paksa rendering software (GPU STB bermasalah)
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
# Diatur oleh pc/client/screen-fix.sh (Panel AHASS)
allowed_users=anybody
needs_root_rights=yes
EOF

cat > "$DROPIN_DIR/client-root.conf" <<'EOF'
# Ditambahkan pc/client/screen-fix.sh: Xorg butuh VT, jadi layar dijalankan sebagai root.
# kiosk.sh menambahkan --no-sandbox otomatis saat berjalan sebagai root.
[Service]
User=root
Group=root
PAMName=
Environment=HOME=/root
Environment=AHASS_PROFILE_DIR=/var/lib/antrianahass-client/chromium
EOF

if attempt "layar sebagai root + xserver-xorg-legacy"; then
  ok "Layar tampil (mode root)."
  echo "root $(date '+%F %T')" > "$STATE_FILE" 2>/dev/null || true
  warn "Untuk kembali ke mode terbatas: sudo bash pc/client/screen-fix.sh --reset"
  exit 0
fi

# ---------------------------------------------------------------- langkah 3
err "Layar belum bisa menampilkan panel setelah 3 langkah."
show_diagnostics
echo "gagal $(date '+%F %T')" > "$STATE_FILE" 2>/dev/null || true
exit 1
