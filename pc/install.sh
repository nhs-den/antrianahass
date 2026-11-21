#!/usr/bin/env bash
#
# Pemasang sisi PC: menjalankan server Panel AHASS di PC (Linux), lalu
# menerima koneksi dari STB di jaringan yang sama.
#
#   sudo bash pc/install.sh                  # pasang + nyalakan server di :8080
#   sudo bash pc/install.sh --no-deps        # lewati apt-get (perbarui kode saja)
#   sudo bash pc/install.sh --port=8080      # ganti port
#   sudo bash pc/install.sh --no-firewall    # jangan sentuh aturan firewall
#   sudo bash pc/install.sh --dry-run        # tampilkan rencana
#
# Aman dijalankan berulang. Konfigurasi di /var/lib/antrianahass tidak ditimpa.
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/antrianahass}"
DATA_DIR="${DATA_DIR:-/var/lib/antrianahass}"
PANEL_USER="${PANEL_USER:-ahass}"
PORT="${PORT:-8080}"
MODE_DEPS=1
MODE_FW=1
DRY=0

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_BIN="/usr/bin/node"

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_info=$'\033[36m'
log()  { echo "${c_info}[pc]${c_reset} $*"; }
ok()   { echo "${c_ok}[ ok ]${c_reset} $*"; }
warn() { echo "${c_warn}[warn]${c_reset} $*"; }
die()  { echo "${c_err}[fail]${c_reset} $*" >&2; exit 1; }
run()  { if [ "$DRY" = "1" ]; then echo "    (dry-run) $*"; else "$@"; fi; }

for arg in "$@"; do
  case "$arg" in
    --no-deps) MODE_DEPS=0 ;;
    --no-firewall) MODE_FW=0 ;;
    --dry-run) DRY=1 ;;
    --port=*) PORT="${arg#*=}" ;;
    --user=*) PANEL_USER="${arg#*=}" ;;
    -h|--help) awk 'NR>1 && NR<=12 && /^#/ {sub(/^# ?/, ""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "Argumen tidak dikenal: $arg (lihat --help)" ;;
  esac
done

if [ "$DRY" != "1" ]; then
  [ "$(id -u)" = "0" ] || die "Jalankan sebagai root: sudo bash pc/install.sh"
fi

echo
log "PC ini akan menjadi server panel; STB hanya menampilkan alamatnya."
log "Memasang dari: $SRC_DIR"

# ------------------------------------------------------------- 1. prasyarat
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64|aarch64|arm64) : ;;
  *) warn "Arsitektur $ARCH belum diuji; Node tetap jalan, Chromium tidak dipakai di PC." ;;
esac

if [ "$MODE_DEPS" = "1" ]; then
  if command -v node >/dev/null 2>&1; then
    NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
    if [ "${NODE_MAJOR:-0}" -lt 18 ]; then
      die "Node.js $(node -v) terlalu tua. Pasang Node 18+ (mis. NodeSource) lalu ulangi."
    fi
    NODE_BIN="$(command -v node)"
    ok "Node.js $(node -v) sudah ada ($NODE_BIN)."
  else
    log "Node.js belum ada, memasang dari repo distro…"
    if [ "$DRY" = "1" ]; then
      echo "    (dry-run) apt-get install -y nodejs"
    else
      apt-get update -qq || true
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs ca-certificates >/dev/null 2>&1 || true
    fi
    if command -v node >/dev/null 2>&1; then
      NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
      NODE_BIN="$(command -v node)"
      ok "Node.js $(node -v) terpasang ($NODE_BIN)."
      [ "${NODE_MAJOR:-0}" -ge 18 ] || warn "Node < 18 dari repo distro. Aplikasi butuh 18+; pertimbangkan nodesource.com."
    else
      die "Node.js gagal dipasang. Pasang manual (nodesource.com) lalu jalankan ulang."
    fi
  fi
else
  command -v node >/dev/null 2>&1 && NODE_BIN="$(command -v node)" || warn "--no-deps: Node.js tidak ditemukan di PATH."
fi

# ------------------------------------------------- 2. pengguna sistem 'ahass'
if [ "$DRY" = "1" ]; then
  echo "    (dry-run) useradd --system --no-create-home --shell /usr/sbin/nologin $PANEL_USER"
elif ! id -u "$PANEL_USER" >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "$PANEL_USER" 2>/dev/null || true
fi
ok "Pengguna sistem $PANEL_USER tersedia."

# --------------------------------------------------------------- 3. salin app
log "Menyalin aplikasi ke $APP_DIR…"
if [ "$DRY" = "1" ]; then
  echo "    (dry-run) rsync/cp $SRC_DIR → $APP_DIR"
else
  mkdir -p "$APP_DIR"
  find "$APP_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
  cp -a "$SRC_DIR/." "$APP_DIR/"
  rm -rf "$APP_DIR/.git" "$APP_DIR/data" "$APP_DIR/node_modules"
  # umask root bisa 077; service berjalan sebagai 'ahass' harus bisa chdir.
  chown -R root:root "$APP_DIR"
  chmod 755 "$APP_DIR"
  chmod -R a+rX "$APP_DIR"
fi
run mkdir -p "$DATA_DIR/uploads" "$DATA_DIR/logos"
ok "Aplikasi tersalin."

# ------------------------------------------------------------------- 4. unit
log "Memasang unit systemd…"
UNIT="$SRC_DIR/pc/units/ahass-pc.service"
[ -f "$UNIT" ] || die "Berkas unit tidak ditemukan: $UNIT"
if [ "$DRY" = "1" ]; then
  echo "    (dry-run) install -m 644 $UNIT /etc/systemd/system/ahass-pc.service"
else
  install -m 644 "$UNIT" /etc/systemd/system/ahass-pc.service
  sed -i "s#^Environment=PORT=.*#Environment=PORT=${PORT}#" /etc/systemd/system/ahass-pc.service
  sed -i "s#^ExecStart=.*#ExecStart=${NODE_BIN} ${APP_DIR}/server.js#" /etc/systemd/system/ahass-pc.service
  sed -i "s#^User=.*#User=${PANEL_USER}#; s#^Group=.*#Group=${PANEL_USER}#" /etc/systemd/system/ahass-pc.service
  sed -i "s#^Environment=AHASS_DATA_DIR=.*#Environment=AHASS_DATA_DIR=${DATA_DIR}#" /etc/systemd/system/ahass-pc.service
  sed -i "s#^Documentation=.*#Documentation=file://${APP_DIR}/pc/README.md#" /etc/systemd/system/ahass-pc.service
fi
run systemctl daemon-reload
run systemctl enable ahass-pc.service
run systemctl restart ahass-pc.service
ok "Layanan ahass-pc terpasang (port $PORT)."

# --------------------------------------------------------------- 5. firewall
if [ "$MODE_FW" = "1" ]; then
  OPENED=0
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "Status: active"; then
    run ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
    OPENED=1
    ok "ufw: port ${PORT}/tcp dibuka."
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    run firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null 2>&1 || true
    run firewall-cmd --reload >/dev/null 2>&1 || true
    OPENED=1
    ok "firewalld: port ${PORT}/tcp dibuka."
  fi
  if [ "$OPENED" = "0" ]; then
    log "Tidak ada ufw/firewalld aktif — tidak ada aturan yang perlu diubah."
  fi
else
  warn "--no-firewall: firewall tidak disentuh. Pastikan port $PORT terbuka."
fi

# ---------------------------------------------------------------- 6. verifikasi
if [ "$DRY" = "1" ]; then
  echo "    (dry-run) tunggu /__ahass/api/health di :$PORT"
else
  log "Menunggu server menjawab…"
  READY=0
  for _ in $(seq 1 30); do
    if command -v curl >/dev/null 2>&1; then
      curl -fs -m 1 -o /dev/null "http://127.0.0.1:${PORT}/__ahass/api/health" 2>/dev/null && { READY=1; break; }
    else
      node -e "require('http').get('http://127.0.0.1:${PORT}/__ahass/api/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))" 2>/dev/null && { READY=1; break; }
    fi
    sleep 1
  done
  [ "$READY" = "1" ] || die "Server belum menjawab di port $PORT. Cek: systemctl status ahass-pc --no-pager && journalctl -u ahass-pc -n 40 --no-pager"
  ok "Server panel menjawab di port $PORT."
fi

IPS="$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1)"
PASS_FILE="$DATA_DIR/ADMIN-PASSWORD.txt"

echo
echo "─────────────────────────────────────────────────────────────"
ok "Server PC siap dipakai STB."
if [ -n "$IPS" ]; then
  echo "$IPS" | while read -r ip; do
    [ -n "$ip" ] && echo "  Alamat LAN  : http://${ip}:${PORT}/"
  done
else
  echo "  Alamat LAN  : (IP PC tidak terdeteksi - cek dengan: ip -4 addr)"
fi
echo "  Admin       : http://IP-PC:${PORT}/admin"
echo "  STB cukup diarahkan ke alamat LAN di atas (jangan 127.0.0.1)."
if [ -r "$PASS_FILE" ]; then
  echo "  Password    : $(head -1 "$PASS_FILE" 2>/dev/null)   (file: $PASS_FILE)"
fi
echo
echo "  Widget ulasan : admin → Ulasan Google → Layanan ulasan (jalankan dari browser)"
echo "                  atau: sudo bash $APP_DIR/deploy/enable-ulasan-autostart.sh --dir <folder>"
echo
echo "  Cek jalur     : node $APP_DIR/pc/doctor.js --port=$PORT"
echo "  Pasang STB    : (di STB) sudo bash pc/client/install.sh --pc=IP-PC"
echo "  Log server    : journalctl -u ahass-pc -n 50 --no-pager"
echo "─────────────────────────────────────────────────────────────"
echo
log "Langkah akhir: buka halaman admin di PC dan isi DDMS, logo, ulasan, kotak 4-5."
