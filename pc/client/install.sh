# Panel AHASS - pemanggil alamat panel di PC dari STB Armbian (Amlogic).
#
# STB tidak menjalankan aplikasi; ia hanya menampilkan alamat LAN PC:
#   http://IP-PC:8080/
#
#   sudo bash pc/client/install.sh --pc=192.168.1.10
#   sudo bash pc/client/install.sh --pc=192.168.1.10 --port=8080
#   sudo bash pc/client/install.sh --pc=192.168.1.10 --dry-run
#   sudo bash pc/client/install.sh --no-fix        # pasang saja, tanpa uji layar
#   sudo bash pc/client/install.sh --no-deps       # lewati apt-get
#   sudo bash pc/client/uninstall.sh               # lepas
#
# Aman dijalankan berulang (mis. setelah IP PC berganti).
set -euo pipefail

PC_HOST=""
PORT="${PORT:-8080}"
MODE_DEPS=1
MODE_FIX=1
DRY=0
PC_SHORT=""
PC_TARGET=""
PROFILE_DIR="${PROFILE_DIR:-/var/lib/antrianahass-client/chromium}"
STATE_DIR="${STATE_DIR:-/var/lib/antrianahass-client}"
KIOSK_USER="${KIOSK_USER:-}"

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_info=$'\033[36m'
log()  { echo "${c_info}[stb]${c_reset} $*"; }
ok()   { echo "${c_ok}[ ok ]${c_reset} $*"; }
warn() { echo "${c_warn}[warn]${c_reset} $*"; }
die()  { echo "${c_err}[fail]${c_reset} $*" >&2; exit 1; }
run()  { if [ "$DRY" = "1" ]; then echo "    (dry-run) $*"; else "$@"; fi; }

for arg in "$@"; do
  case "$arg" in
    --pc=*) PC_HOST="${arg#*=}" ;;
    --port=*) PORT="${arg#*=}" ;;
    --user=*) KIOSK_USER="${arg#*=}" ;;
    --no-deps) MODE_DEPS=0 ;;
    --no-fix) MODE_FIX=0 ;;
    --dry-run) DRY=1 ;;
    -h|--help) awk 'NR>1 && NR<=14 && /^#/ {sub(/^# ?/, ""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    http://*|https://*) PC_HOST="${arg#*//}" ; PC_HOST="${PC_HOST%%/*}" ;;
    *) die "Argumen tidak dikenal: $arg (lihat --help)" ;;
  esac
done

[ -n "$PC_HOST" ] || die "Alamat PC wajib: sudo bash pc/client/install.sh --pc=192.168.1.10"
PC_HOST="${PC_HOST%%:*}"          # buang port bila ditulis 192.168.1.10:8080
URL="http://${PC_HOST}:${PORT}/"

if [ "$DRY" != "1" ]; then
  [ "$(id -u)" = "0" ] || die "Jalankan sebagai root: sudo bash pc/client/install.sh --pc=IP-PC"
fi

# Nama NetBIOS PC bisa berbeda dari nama host yang diketik user (mis. "PC-KASIR"
# vs "DESKTOP-AB12CD"). Uji dua-duanya, pakai yang benar-benar menjawab.
PC_SHORT="${PC_HOST%%.*}"
PC_TARGET="http://${PC_HOST}:${PORT}/"
if [ "$PC_SHORT" != "$PC_HOST" ] && command -v curl >/dev/null 2>&1; then
  if ! curl -fs -m 4 -o /dev/null "http://${PC_HOST}:${PORT}/__ahass/api/health" 2>/dev/null \
     && curl -fs -m 4 -o /dev/null "http://${PC_SHORT}:${PORT}/__ahass/api/health" 2>/dev/null; then
    warn "Nama panjang tidak menjawab, tetapi '$PC_SHORT' menjawab - memakai itu."
    PC_HOST="$PC_SHORT"
    URL="http://${PC_HOST}:${PORT}/"
    PC_TARGET="$URL"
  fi
fi

echo
log "STB akan menampilkan: $URL"
log "Tidak ada aplikasi yang dipasang di STB - hanya Chromium kiosk."

# ------------------------------------------------------------ 1. pengguna layar
if [ -z "$KIOSK_USER" ]; then
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    KIOSK_USER="$SUDO_USER"
  elif id -u kiosk >/dev/null 2>&1; then
    KIOSK_USER="kiosk"
  elif id -u armbian >/dev/null 2>&1; then
    KIOSK_USER="armbian"
  else
    KIOSK_USER="kiosk"
  fi
fi

if ! id -u "$KIOSK_USER" >/dev/null 2>&1; then
  log "Membuat pengguna layar '$KIOSK_USER'…"
  run useradd --create-home --shell /bin/bash "$KIOSK_USER" 2>/dev/null || true
fi

if [ "$DRY" != "1" ]; then
  usermod -aG video,audio,input,render,netdev "$KIOSK_USER" 2>/dev/null || true
fi

KIOSK_HOME="$(getent passwd "$KIOSK_USER" 2>/dev/null | cut -d: -f6 || true)"
[ -n "$KIOSK_HOME" ] || KIOSK_HOME="/home/$KIOSK_USER"
PROFILE_DIR="${KIOSK_HOME}/.config/ahass-kiosk"
ok "Pengguna layar: $KIOSK_USER ($KIOSK_HOME)"
ok "Profil Chromium: $PROFILE_DIR"

# --------------------------------------------------------------- 2. paket dasar
if [ "$MODE_DEPS" = "1" ]; then
  log "Memeriksa paket (Chromium, X, xinit, xwd)…"
  MISSING=""
  command -v chromium >/dev/null 2>&1 || command -v chromium-browser >/dev/null 2>&1 || MISSING="$MISSING chromium"
  command -v xinit >/dev/null 2>&1 || MISSING="$MISSING xinit"
  command -v xset >/dev/null 2>&1 || MISSING="$MISSING x11-xserver-utils"
  command -v xwd >/dev/null 2>&1 || MISSING="$MISSING x11-apps"
  [ -f /usr/bin/Xorg ] || [ -f /usr/lib/xorg/Xorg ] || MISSING="$MISSING xserver-xorg"

  if [ -n "$MISSING" ]; then
    log "Memasang:$MISSING"
    if [ "$DRY" = "1" ]; then
      echo "    (dry-run) apt-get install -y$MISSING"
    else
      apt-get update -qq || true
      # shellcheck disable=SC2086
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        $MISSING unclutter xauth fonts-dejavu-core ca-certificates curl >/dev/null 2>&1 \
        || warn "Sebagian paket gagal dipasang; periksa manual dengan apt-get."
    fi
  fi

  if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
    warn "Chromium tidak ditemukan setelah apt. Di image Ubuntu, chromium hanya snap:"
    warn "  snap install chromium   (berat, butuh ±1 GB)"
  fi
else
  warn "--no-deps: paket tidak diperiksa."
fi

# ------------------------------------------------------------ 3. skrip & unit
log "Memasang skrip layar dan unit systemd…"
run mkdir -p "$STATE_DIR" "$PROFILE_DIR" /etc/ahass-client
if [ "$DRY" != "1" ]; then
  chown -R "$KIOSK_USER:$KIOSK_USER" "$STATE_DIR" "$PROFILE_DIR" 2>/dev/null || true
fi

if [ "$DRY" = "1" ]; then
  echo "    (dry-run) install -m 755 $SRC_DIR/pc/client/kiosk.sh /usr/local/bin/ahass-pc-kiosk.sh"
  echo "    (dry-run) install -m 755 $SRC_DIR/pc/client/wait-panel.sh /usr/local/bin/ahass-pc-wait-panel.sh"
  echo "    (dry-run) install -m 755 $SRC_DIR/pc/client/screen-fix.sh /usr/local/bin/ahass-pc-screen-fix.sh"
else
  install -m 755 "$SRC_DIR/pc/client/kiosk.sh" /usr/local/bin/ahass-pc-kiosk.sh
  install -m 755 "$SRC_DIR/pc/client/wait-panel.sh" /usr/local/bin/ahass-pc-wait-panel.sh
  install -m 755 "$SRC_DIR/pc/client/screen-fix.sh" /usr/local/bin/ahass-pc-screen-fix.sh
fi

FLAGS="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$SRC_DIR/pc/client/chromium-flags.conf" | tr '\n' ' ' | sed 's/  */ /g' || true)"

UNIT_SRC="$SRC_DIR/pc/client/ahass-pc-kiosk.service"
[ -f "$UNIT_SRC" ] || die "Unit tidak ditemukan: $UNIT_SRC"

render_unit() {
  sed -e "s#__KIOSK_USER__#${KIOSK_USER}#g" \
      -e "s#__PROFILE_DIR__#${PROFILE_DIR}#g" \
      -e "s#__PANEL_URL__#${URL}#g" \
      -e "s#__CHROMIUM_FLAGS__#${FLAGS}#g" \
      "$UNIT_SRC"
}

if [ "$DRY" = "1" ]; then
  echo "    (dry-run) tulis /etc/systemd/system/ahass-pc-kiosk.service (URL=$URL)"
else
  render_unit > /etc/systemd/system/ahass-pc-kiosk.service
  # Tulis URL juga ke berkas kecil agar mudah diubah tanpa menyentuh unit.
  printf '%s\n' "$URL" > /etc/ahass-client/panel-url
fi
ok "Unit ahass-pc-kiosk terpasang (URL: $URL)."

# Matikan kiosk lama (mode mandiri) supaya tidak berebut tty1/X.
for old in ahass-kiosk.service ahass-panel.service; do
  if systemctl list-unit-files 2>/dev/null | grep -q "^${old}"; then
    warn "$old (mode mandiri) ditemukan - dimatikan agar tidak bentrok."
    run systemctl disable --now "$old" 2>/dev/null || true
  fi
done

run systemctl daemon-reload
run systemctl enable ahass-pc-kiosk.service
run systemctl restart ahass-pc-kiosk.service
ok "Layanan layar dinyalakan."

# -------------------------------------------------------------- 4. jaringan
if [ "$DRY" != "1" ]; then
  HEALTH="$(curl -fs -m 5 "${PC_TARGET}__ahass/api/health" 2>/dev/null || true)"
  if [ -n "$HEALTH" ]; then
    ok "PC menjawab dari STB: $(printf '%s' "$HEALTH" | cut -c1-100)"
  else
    warn "PC ($PC_HOST:$PORT) BELUM menjawab dari STB. Periksa:"
    warn "  1. Server di PC hidup        : systemctl status ahass-pc   (atau Service 'AhassPanel' di Windows)"
    warn "  2. Alamat IP PC benar        : node pc/doctor.js  (di PC)"
    warn "  3. Firewall PC membuka $PORT  : ufw allow ${PORT}/tcp"
    warn "  4. STB & PC satu jaringan     : ping ${PC_HOST}"
    warn "Layar tetap dipasang; perbaiki jaringan lalu: sudo systemctl restart ahass-pc-kiosk"
  fi
fi

# --------------------------------------------------------------- 5. uji layar
if [ "$MODE_FIX" = "1" ] && [ "$DRY" != "1" ]; then
  log "Menguji layar (bisa 1-3 menit)…"
  if bash /usr/local/bin/ahass-pc-screen-fix.sh 2>/dev/null; then
    ok "Layar STB menampilkan panel PC."
  else
    warn "Layar belum terverifikasi. Jalankan: sudo bash /usr/local/bin/ahass-pc-screen-fix.sh"
  fi
elif [ "$DRY" = "1" ]; then
  echo "    (dry-run) uji layar: ahass-pc-screen-fix.sh"
fi

echo
echo "─────────────────────────────────────────────────────────────"
ok "STB siap menampilkan panel dari PC."
echo "  Alamat     : $URL"
echo "  Admin      : ${URL}admin    (buka dari PC atau browser mana pun)"
echo "  Diagnosa   : sudo bash $SRC_DIR/pc/client/screen-fix.sh"
echo "  Log layar  : journalctl -u ahass-pc-kiosk -n 40 --no-pager"
echo "  Lepas      : sudo bash $SRC_DIR/pc/client/uninstall.sh"
echo
echo "Kalau IP PC berubah (DHCP), beri IP statis atau jalankan ulang:"
echo "  sudo bash pc/client/install.sh --pc=IP-PC-BARU"
echo "─────────────────────────────────────────────────────────────"
