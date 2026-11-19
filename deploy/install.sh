#!/usr/bin/env bash
#
# Pemasang Panel AHASS untuk DietPi / Debian (Intel Compute Stick).
#
#   sudo bash deploy/install.sh              # pasang / perbarui semuanya
#   sudo bash deploy/install.sh --no-deps    # lewati instalasi paket apt
#
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/antrianahass}"
DATA_DIR="${DATA_DIR:-/var/lib/antrianahass}"
PORT="${PORT:-8080}"
PANEL_USER="${PANEL_USER:-ahass}"
KIOSK_USER="${KIOSK_USER:-kiosk}"
INSTALL_DEPS=1

for arg in "$@"; do
  case "$arg" in
    --no-deps) INSTALL_DEPS=0 ;;
    -h|--help)
      echo "Penggunaan: sudo bash deploy/install.sh [--no-deps]"
      exit 0
      ;;
  esac
done

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_info=$'\033[36m'
log()  { echo "${c_info}[ahass]${c_reset} $*"; }
ok()   { echo "${c_ok}[ ok ]${c_reset} $*"; }
warn() { echo "${c_warn}[warn]${c_reset} $*"; }
die()  { echo "${c_err}[fail]${c_reset} $*" >&2; exit 1; }

if [ "$(id -u)" != "0" ]; then
  die "Jalankan sebagai root: sudo bash deploy/install.sh"
fi

ARCH="$(uname -m)"
log "Arsitektur: $ARCH"
case "$ARCH" in
  x86_64|amd64|aarch64|arm64|armv7l) ;;
  *) warn "Arsitektur $ARCH belum diuji; lanjutkan dengan hati-hati." ;;
esac

# ---------------------------------------------------------------- 1. paket
if [ "$INSTALL_DEPS" = "1" ]; then
  log "Memperbarui daftar paket…"
  apt-get update -qq || warn "apt-get update gagal, lanjut dengan cache lama."

  PACKAGES="ca-certificates fonts-dejavu-core xserver-xorg xinit xauth x11-xserver-utils unclutter"

  if ! command -v node >/dev/null 2>&1; then
    PACKAGES="$PACKAGES nodejs"
  fi
  if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
    PACKAGES="$PACKAGES chromium"
  fi

  log "Memasang paket: $PACKAGES"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $PACKAGES || {
    warn "Sebagian paket gagal dipasang. Mencoba tanpa paket grafis…"
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates || true
  }
fi

if ! command -v node >/dev/null 2>&1; then
  die "Node.js belum tersedia. Pasang dulu: apt-get install -y nodejs (minimal versi 18)."
fi

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [ "$NODE_MAJOR" -lt 18 ]; then
  die "Node.js versi $(node -v) terlalu lama. Dibutuhkan minimal v18."
fi
ok "Node.js $(node -v)"

if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
  warn "Chromium tidak ditemukan — layar kiosk tidak akan tampil sebelum Chromium dipasang."
  warn "Pasang manual: apt-get install -y chromium"
fi

# ------------------------------------------------------------ 2. pengguna
if ! id -u "$PANEL_USER" >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "$PANEL_USER"
  ok "Pengguna sistem $PANEL_USER dibuat."
fi

if ! id -u "$KIOSK_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --groups video,audio,input,render "$KIOSK_USER" 2>/dev/null \
    || useradd --create-home --shell /bin/bash "$KIOSK_USER"
  ok "Pengguna kiosk $KIOSK_USER dibuat."
fi

# ------------------------------------------------------------- 3. salin app
log "Menyalin aplikasi ke $APP_DIR…"
mkdir -p "$APP_DIR"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete \
    --exclude '.git' --exclude 'node_modules' --exclude 'data' \
    --exclude 'deploy' --exclude '.DS_Store' \
    "$SRC_DIR/" "$APP_DIR/"
  mkdir -p "$APP_DIR/deploy"
  rsync -a "$SRC_DIR/deploy/" "$APP_DIR/deploy/"
else
  find "$APP_DIR" -mindepth 1 -maxdepth 1 ! -name deploy -exec rm -rf {} +
  cp -a "$SRC_DIR/." "$APP_DIR/"
  rm -rf "$APP_DIR/.git" "$APP_DIR/data" "$APP_DIR/node_modules"
fi

mkdir -p "$DATA_DIR/uploads" "$DATA_DIR/chromium"
chown -R root:root "$APP_DIR"
chown -R "$PANEL_USER:$PANEL_USER" "$DATA_DIR"
chmod 750 "$DATA_DIR"
chmod +x "$APP_DIR/deploy/start-kiosk.sh" 2>/dev/null || true
chown -R "$KIOSK_USER:$KIOSK_USER" "$DATA_DIR/chromium"
ok "Aplikasi tersalin."

# ------------------------------------------------------------- 4. systemd
log "Memasang layanan systemd…"
install -m 644 "$SRC_DIR/deploy/ahass-panel.service" /etc/systemd/system/ahass-panel.service
install -m 644 "$SRC_DIR/deploy/ahass-kiosk.service" /etc/systemd/system/ahass-kiosk.service
install -m 644 "$SRC_DIR/deploy/ahass-restart.service" /etc/systemd/system/ahass-restart.service
install -m 644 "$SRC_DIR/deploy/ahass-restart.timer" /etc/systemd/system/ahass-restart.timer

# sesuaikan port bila berbeda dari default
if [ "$PORT" != "8080" ]; then
  sed -i "s/^Environment=PORT=.*/Environment=PORT=$PORT/" /etc/systemd/system/ahass-panel.service
  sed -i "s#Environment=AHASS_URL=.*#Environment=AHASS_URL=http://127.0.0.1:$PORT/#" /etc/systemd/system/ahass-kiosk.service
fi
if [ "$PANEL_USER" != "ahass" ]; then
  sed -i "s/^User=ahass$/User=$PANEL_USER/; s/^Group=ahass$/Group=$PANEL_USER/" /etc/systemd/system/ahass-panel.service
fi
if [ "$KIOSK_USER" != "kiosk" ]; then
  sed -i "s/^User=kiosk$/User=$KIOSK_USER/; s/^Group=kiosk$/Group=$KIOSK_USER/" /etc/systemd/system/ahass-kiosk.service
fi
if [ "$DATA_DIR" != "/var/lib/antrianahass" ]; then
  sed -i "s#/var/lib/antrianahass#$DATA_DIR#g" /etc/systemd/system/ahass-panel.service /etc/systemd/system/ahass-kiosk.service
fi

systemctl daemon-reload
systemctl enable ahass-panel.service >/dev/null 2>&1
systemctl enable ahass-kiosk.service >/dev/null 2>&1
systemctl enable ahass-restart.timer >/dev/null 2>&1
ok "Layanan terpasang."

# --------------------------------------------------------------- 5. jalan
log "Menjalankan server panel…"
systemctl restart ahass-panel.service
sleep 2

if systemctl is-active --quiet ahass-panel.service; then
  ok "Server panel aktif di port $PORT."
else
  warn "Server panel tidak aktif. Periksa: journalctl -u ahass-panel -n 40 --no-pager"
fi

if command -v chromium >/dev/null 2>&1 || command -v chromium-browser >/dev/null 2>&1; then
  if [ "${AHASS_SKIP_KIOSK:-0}" != "1" ]; then
    log "Menjalankan layar kiosk…"
    systemctl restart ahass-kiosk.service || true
    sleep 5
    KIOSK_STATE="$(systemctl show -p SubState --value ahass-kiosk.service 2>/dev/null || echo unknown)"
    if [ "$KIOSK_STATE" != "running" ]; then
      warn "Layar kiosk belum berjalan (state: $KIOSK_STATE)."
      echo "----- 12 baris log terakhir ahass-kiosk -----"
      journalctl -u ahass-kiosk -n 12 --no-pager 2>/dev/null || true
      echo "---------------------------------------------"
      warn "Coba perbaiki otomatis: sudo bash $APP_DIR/deploy/fix-kiosk.sh"
    else
      ok "Layar kiosk berjalan."
    fi
  fi
else
  warn "Lewati layar kiosk (Chromium belum ada)."
fi

# -------------------------------------------------------------- 6. ringkas
IP_ADDR="$(hostname -I 2>/dev/null | awk '{print $1}')"
PASSWORD_FILE="$DATA_DIR/ADMIN-PASSWORD.txt"

echo
echo "─────────────────────────────────────────────────────────────"
ok "Panel AHASS siap dipakai."
echo "  Panel tampilan : http://${IP_ADDR:-localhost}:$PORT/"
echo "  Halaman admin  : http://${IP_ADDR:-localhost}:$PORT/admin"
if [ -f "$PASSWORD_FILE" ]; then
  echo "  Password admin : $(grep -m1 'Password : ' "$PASSWORD_FILE" | sed 's/Password : //')"
  echo "                   (tersimpan juga di $PASSWORD_FILE)"
else
  echo "  Password admin : password yang Anda tetapkan sebelumnya"
fi
echo
echo "  Status  : systemctl status ahass-panel ahass-kiosk"
echo "  Log     : journalctl -u ahass-panel -f"
echo "  Ulangi  : sudo bash $APP_DIR/deploy/install.sh --no-deps"
echo "─────────────────────────────────────────────────────────────"
echo
echo "Catatan DietPi: bila desktop/LXDE ikut berjalan otomatis, matikan dulu"
echo "melalui 'dietpi-autostart' (pilih mode Manual/Console) agar tidak bentrok"
echo "dengan layar kiosk."
