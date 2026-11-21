#!/usr/bin/env bash
#
# Pemasang Panel AHASS untuk STB Amlogic (S905X/S905W/S912) ber-Armbian ophub.
#
#   sudo bash stb/install.sh                 # pasang + perbaiki layar sampai tampil
#   sudo bash stb/install.sh --no-fix        # pasang saja, tanpa auto-perbaikan layar
#   sudo bash stb/install.sh --no-deps       # lewati apt-get (perbarui kode saja)
#   sudo bash stb/install.sh --user=kiosk    # tentukan pengguna yang menjalankan layar
#   sudo bash stb/install.sh --port=8080     # ganti port panel
#   sudo bash stb/install.sh --resolution=1920x1080   # paksa resolusi HDMI (opsional)
#   sudo bash stb/install.sh --dry-run       # tampilkan rencana, tidak mengubah sistem
#
# Aman dijalankan berulang. Konfigurasi di /var/lib/antrianahass tidak disentuh.
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/antrianahass}"
DATA_DIR="${DATA_DIR:-/var/lib/antrianahass}"
PORT="${PORT:-8080}"
PANEL_USER="${PANEL_USER:-ahass}"
KIOSK_USER="${KIOSK_USER:-}"
MODE_FIX=1
INSTALL_DEPS=1
DRY=0
RESOLUTION=""

NODE_BIN="/usr/bin/node"

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STB_DIR="$SRC_DIR/stb"

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_info=$'\033[36m'
log()  { echo "${c_info}[ahass]${c_reset} $*"; }
ok()   { echo "${c_ok}[ ok ]${c_reset} $*"; }
warn() { echo "${c_warn}[warn]${c_reset} $*"; }
die()  { echo "${c_err}[fail]${c_reset} $*" >&2; exit 1; }
run()  { if [ "$DRY" = "1" ]; then echo "    (dry-run) $*"; else "$@"; fi; }

for arg in "$@"; do
  case "$arg" in
    --no-fix) MODE_FIX=0 ;;
    --no-deps) INSTALL_DEPS=0 ;;
    --dry-run) DRY=1 ;;
    --user=*) KIOSK_USER="${arg#*=}" ;;
    --port=*) PORT="${arg#*=}" ;;
    --resolution=*) RESOLUTION="${arg#*=}" ;;
    -h|--help) awk 'NR>1 && NR<=18 && /^#/ {sub(/^# ?/, ""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "Argumen tidak dikenal: $arg (lihat --help)" ;;
  esac
done

if [ "$DRY" != "1" ]; then
  [ "$(id -u)" = "0" ] || die "Jalankan sebagai root: sudo bash stb/install.sh"
fi

# --------------------------------------------------------- 1. deteksi perangkat
MODEL="$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || true)"
COMPAT="$(cat /proc/device-tree/compatible 2>/dev/null | tr -d '\0' || true)"
MODEL="${MODEL:-tidak diketahui}"
ARCH="$(uname -m)"
MEM_MB="$(awk '/^MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo)"
DISK_FREE_MB="$(df -Pm / | awk 'NR==2 {print $4}')"
OS_NAME="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-$ID}")"
OS_ID="$(. /etc/os-release 2>/dev/null && echo "${ID:-unknown}")"
OS_CODENAME="$(. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-}")"

log "Perangkat : $MODEL"
log "Compatible: ${COMPAT:-tidak diketahui}"
log "Arsitektur: $ARCH"
log "RAM       : ${MEM_MB} MB"
log "Ruang /   : ${DISK_FREE_MB} MB bebas"
log "Sistem    : ${OS_NAME:-tidak diketahui}"

case "$ARCH" in
  aarch64|arm64) ok "ARM64 - cocok untuk Chromium arm64." ;;
  armv7l) warn "ARM 32-bit: Chromium 32-bit jauh lebih boros memori. Arm64 dianjurkan." ;;
  x86_64|amd64) warn "x86_64: folder stb/ ditujukan untuk STB ARM; di x86 pakai deploy/install.sh untuk hasil terbaik." ;;
  *) die "Arsitektur $ARCH tidak didukung pemasang ini." ;;
esac

case "$COMPAT$MODEL" in
  *amlogic*|*s905*|*s912*|*S905*|*S912*) ok "SoC Amlogic terdeteksi." ;;
  *) warn "Bukan Amlogic yang terdeteksi; setelan tetap dipakai (Armbian/Debian apa pun)." ;;
esac

if [ "${DISK_FREE_MB:-0}" -lt 1800 ]; then
  warn "Ruang kosong < 1,8 GB. Chromium + Node butuh sekitar 700 MB saat pemasangan."
fi

# --------------------------------------------------------------- 2. paket apt
SNAP_CHROMIUM=0
if [ "$INSTALL_DEPS" = "1" ] && [ "$DRY" != "1" ]; then
  log "Memperbarui daftar paket…"
  apt-get update -qq || warn "apt-get update gagal, memakai cache lama."

  PACKAGES="ca-certificates curl fonts-dejavu-core logrotate git \
xserver-xorg xinit xauth x11-xserver-utils x11-apps"

  command -v unclutter >/dev/null 2>&1 || PACKAGES="$PACKAGES unclutter"
  command -v node >/dev/null 2>&1 || PACKAGES="$PACKAGES nodejs"
  if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
    PACKAGES="$PACKAGES chromium"
  fi

  log "Memasang paket: $PACKAGES"
  # shellcheck disable=SC2086
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $PACKAGES \
    || warn "Sebagian paket gagal dipasang; lanjut dan periksa hasil deteksi di bawah."
fi

command -v node >/dev/null 2>&1 || { [ "$DRY" = "1" ] || die "Node.js tidak ada. Pasang: sudo apt-get install -y nodejs"; }
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
  [ "$NODE_MAJOR" -ge 18 ] || die "Node.js $(node -v) terlalu lama; butuh minimal v18."
  NODE_BIN="$(command -v node || echo /usr/bin/node)"
ok "Node.js $(node -v) ($NODE_BIN)"
fi

CHROME_PATH=""
for candidate in chromium chromium-browser google-chrome-stable; do
  if command -v "$candidate" >/dev/null 2>&1; then CHROME_PATH="$(readlink -f "$(command -v "$candidate")")"; break; fi
done

if [ -z "$CHROME_PATH" ]; then
  warn "Chromium belum ada - layar tidak mungkin tampil."
  warn "Debian: sudo apt-get install -y chromium"
  warn "Ubuntu : 'chromium' hanya snap (berat). Sebaiknya pakai image Armbian Debian."
  [ "$MODE_FIX" = "1" ] && warn "Auto-perbaikan layar akan dilewati."
  MODE_FIX=0
else
  case "$CHROME_PATH" in
    /snap/*|*/snap/*) SNAP_CHROMIUM=1; warn "Chromium berasal dari SNAP ($CHROME_PATH)." ;;
  esac
  if [ "$SNAP_CHROMIUM" = "1" ]; then
    warn "Snap Chromium memaksa profil di dalam home pengguna dan lebih lambat."
    warn "Bila memungkinkan, pakai image Armbian berbasis Debian (chromium apt)."
  fi
  ok "Chromium: $CHROME_PATH"
fi

if [ "$OS_ID" = "ubuntu" ]; then
  warn "Basis Ubuntu terdeteksi ($OS_CODENAME). Chromium apt di Ubuntu = snap."
fi

# ----------------------------------------------------------- 3. pengguna layar
if ! id -u "$PANEL_USER" >/dev/null 2>&1; then
  run useradd --system --no-create-home --shell /usr/sbin/nologin "$PANEL_USER"
  log "Pengguna sistem $PANEL_USER dibuat."
fi

if [ -z "$KIOSK_USER" ]; then
  for candidate in "${SUDO_USER:-}" kiosk armbian dietpi; do
    if [ -n "$candidate" ] && [ "$candidate" != "root" ] && id -u "$candidate" >/dev/null 2>&1; then
      KIOSK_USER="$candidate"
      break
    fi
  done
fi
if [ -z "$KIOSK_USER" ]; then
  KIOSK_USER="$(awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd)"
fi
if [ -z "$KIOSK_USER" ]; then
  # Armbian ophub default hanya punya root: buat pengguna sendiri agar layar tidak jalan sebagai root.
  KIOSK_USER="kiosk"
  warn "Tidak ada pengguna biasa; membuat '$KIOSK_USER' agar Chromium tidak berjalan sebagai root."
  run adduser --gecos "" --disabled-password "$KIOSK_USER"
fi

id -u "$KIOSK_USER" >/dev/null 2>&1 || die "Pengguna $KIOSK_USER tidak ada."
KIOSK_HOME="$(getent passwd "$KIOSK_USER" | cut -d: -f6)"
[ -n "$KIOSK_HOME" ] || die "Home $KIOSK_USER tidak ditemukan."
run usermod -aG video,audio,input,render,netdev "$KIOSK_USER" 2>/dev/null || true

if [ "$SNAP_CHROMIUM" = "1" ]; then
  PROFILE_DIR="$KIOSK_HOME/.config/ahass-kiosk"
else
  PROFILE_DIR="$DATA_DIR/chromium"
fi

log "Pengguna layar: $KIOSK_USER ($KIOSK_HOME)"
log "Profil Chromium: $PROFILE_DIR"

# ------------------------------------------------------------- 4. salin app
log "Menyalin aplikasi ke $APP_DIR…"
run mkdir -p "$APP_DIR"
if command -v rsync >/dev/null 2>&1; then
  run rsync -a --delete \
    --exclude '.git' --exclude 'node_modules' --exclude 'data' --exclude '.DS_Store' \
    "$SRC_DIR/" "$APP_DIR/"
else
  run bash -c "find '$APP_DIR' -mindepth 1 -maxdepth 1 -exec rm -rf {} +"
  run cp -a "$SRC_DIR/." "$APP_DIR/"
  run rm -rf "$APP_DIR/.git" "$APP_DIR/data" "$APP_DIR/node_modules"
fi

run mkdir -p "$DATA_DIR/uploads" "$DATA_DIR/chromium" /etc/ahass
if [ "$DRY" != "1" ]; then
  chown -R root:root "$APP_DIR"
  # umask root bisa 077 (DietPi): folder 0700 membuat service gagal chdir.
  chmod 755 "$APP_DIR" && chmod -R a+rX "$APP_DIR"
  chown -R "$PANEL_USER:$PANEL_USER" "$DATA_DIR"
  chmod 750 "$DATA_DIR"
  chown -R "$KIOSK_USER:$KIOSK_USER" "$DATA_DIR/chromium"
  chmod +x "$APP_DIR/deploy/start-kiosk.sh" 2>/dev/null || true
fi
ok "Aplikasi tersalin."

# ------------------------------------------------ 5. flag Chromium sesuai RAM
if [ "$MEM_MB" -ge 1800 ]; then
  FLAGS_RENDERER=2
  FLAGS_HEAP=256
else
  FLAGS_RENDERER=1
  FLAGS_HEAP=128
fi

if [ "$DRY" = "1" ]; then
  log "Flag Chromium: renderer=$FLAGS_RENDERER heap=${FLAGS_HEAP}MB"
else
  install -m 644 "$STB_DIR/chromium-flags.conf" /etc/ahass/chromium-flags.conf
  sed -i "s/^--renderer-process-limit=.*/--renderer-process-limit=$FLAGS_RENDERER/" /etc/ahass/chromium-flags.conf
  sed -i "s/^--js-flags=.*/--js-flags=--max-old-space-size=$FLAGS_HEAP/" /etc/ahass/chromium-flags.conf
fi
ok "Flag Chromium: renderer=$FLAGS_RENDERER, heap ${FLAGS_HEAP} MB."

CHROMIUM_FLAGS_LINE="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$STB_DIR/chromium-flags.conf" \
  | sed -e "s/^--renderer-process-limit=.*/--renderer-process-limit=$FLAGS_RENDERER/" \
        -e "s/^--js-flags=.*/--js-flags=--max-old-space-size=$FLAGS_HEAP/" \
  | tr '\n' ' ' | sed 's/  */ /g')"

# --------------------------------------------------------------- 6. systemd
log "Memasang unit systemd…"
run install -m 644 "$STB_DIR/units/ahass-panel.service" /etc/systemd/system/ahass-panel.service
run install -m 644 "$STB_DIR/units/ahass-restart.service" /etc/systemd/system/ahass-restart.service
run install -m 644 "$STB_DIR/units/ahass-restart.timer" /etc/systemd/system/ahass-restart.timer
run install -m 644 "$STB_DIR/units/ahass-kiosk.service" /etc/systemd/system/ahass-kiosk.service
run install -m 755 "$STB_DIR/scripts/wait-panel.sh" /usr/local/bin/ahass-wait-panel.sh

if [ "$DRY" != "1" ]; then
  sed -i "s#__KIOSK_USER__#$KIOSK_USER#g" /etc/systemd/system/ahass-kiosk.service
  sed -i "s#__PROFILE_DIR__#$PROFILE_DIR#g" /etc/systemd/system/ahass-kiosk.service
  sed -i "s#__CHROMIUM_FLAGS__#$CHROMIUM_FLAGS_LINE#g" /etc/systemd/system/ahass-kiosk.service
  sed -i "s#__KIOSK_HOME__#$KIOSK_HOME#g" /etc/systemd/system/ahass-restart.service

  if [ "$PORT" != "8080" ]; then
    sed -i "s/^Environment=PORT=.*/Environment=PORT=$PORT/" /etc/systemd/system/ahass-panel.service
    sed -i "s#^Environment=AHASS_URL=.*#Environment=AHASS_URL=http://127.0.0.1:$PORT/#" /etc/systemd/system/ahass-kiosk.service
  fi
  if [ "$PANEL_USER" != "ahass" ]; then
    sed -i "s/^User=ahass$/User=$PANEL_USER/; s/^Group=ahass$/Group=$PANEL_USER/" /etc/systemd/system/ahass-panel.service
  fi
  if [ "$DATA_DIR" != "/var/lib/antrianahass" ]; then
    sed -i "s#/var/lib/antrianahass#$DATA_DIR#g" /etc/systemd/system/ahass-panel.service
  fi

  sed -i "s#^ExecStart=.*#ExecStart=$NODE_BIN /opt/antrianahass/server.js#" /etc/systemd/system/ahass-panel.service

  systemctl daemon-reload
  systemctl enable ahass-panel.service >/dev/null 2>&1
  systemctl enable ahass-restart.timer >/dev/null 2>&1
  systemctl enable ahass-kiosk.service >/dev/null 2>&1
fi
ok "Unit ahass-panel, ahass-kiosk, ahass-restart terpasang."

# --------------------------------------------------------- 7. tweak ringan OS
if [ "$DRY" != "1" ]; then
  install -d -m 755 /etc/systemd/journald.conf.d
  install -m 644 "$STB_DIR/journald-ahass-small.conf" /etc/systemd/journald.conf.d/ahass-small.conf
  systemctl restart systemd-journald >/dev/null 2>&1 || true
  install -m 644 "$STB_DIR/sysctl-ahass-stb.conf" /etc/sysctl.d/99-ahass-stb.conf
  sysctl --system >/dev/null 2>&1 || true
  ok "Tweak jurnal (64 MB) + sysctl terpasang."
fi

# ---------------------------------------------------------- 8. resolusi HDMI
if [ -n "$RESOLUTION" ] && [ "$DRY" != "1" ]; then
  log "Mencoba menetapkan resolusi HDMI $RESOLUTION…"
  BOOT_ENV=""
  for f in /boot/uEnv.txt /boot/armbianEnv.txt /boot/firmware/armbianEnv.txt; do
    [ -f "$f" ] && BOOT_ENV="$f" && break
  done
  if [ -z "$BOOT_ENV" ]; then
    warn "Berkas env boot tidak ditemukan; atur resolusi manual."
  elif grep -q "video=HDMI" "$BOOT_ENV"; then
    sed -i "s#video=HDMI[^ ]*#video=HDMI-A-1:$RESOLUTION@60e#" "$BOOT_ENV"
    ok "Resolusi diperbarui di $BOOT_ENV (berlaku setelah reboot)."
  else
    cp "$BOOT_ENV" "$BOOT_ENV.bak-ahass"
    if grep -q '^extraargs=' "$BOOT_ENV"; then
      sed -i "s#^extraargs=.*#& video=HDMI-A-1:$RESOLUTION@60e#" "$BOOT_ENV"
    else
      printf 'extraargs=video=HDMI-A-1:%s@60e\n' "$RESOLUTION" >> "$BOOT_ENV"
    fi
    ok "video=HDMI-A-1:$RESOLUTION@60e ditambahkan ke $BOOT_ENV (backup: $BOOT_ENV.bak-ahass)."
  fi
fi

# --------------------------------------------------------------- 9. panel up
log "Menjalankan server panel…"
run systemctl restart ahass-panel.service

HEALTH_OK=0
if [ "$DRY" != "1" ]; then
  i=0
  while [ "$i" -lt 30 ]; do
    if curl -fs -m 2 -o /dev/null "http://127.0.0.1:$PORT/__ahass/api/health" 2>/dev/null; then
      HEALTH_OK=1
      break
    fi
    i=$((i + 1))
    sleep 1
  done
  if [ "$HEALTH_OK" = "1" ]; then
    ok "Panel aktif di port $PORT."
  else
    warn "Panel belum menjawab: journalctl -u ahass-panel -n 40 --no-pager"
  fi
fi

# ------------------------------------------------- 10. perbaiki sampai tampil
SCREEN_RESULT="tidak dijalankan"
if [ "$MODE_FIX" = "1" ] && [ "$DRY" != "1" ]; then
  echo
  log "Memastikan layar benar-benar menampilkan panel…"
  if bash "$APP_DIR/stb/screen-fix.sh" --port="$PORT"; then
    SCREEN_RESULT="tampil"
  else
    SCREEN_RESULT="gagal"
  fi
elif [ "$DRY" = "1" ]; then
  log "(dry-run) layar akan diuji dan diperbaiki otomatis (screen-fix.sh)."
else
  log "Menyalakan layar (tanpa auto-perbaikan)…"
  run systemctl restart ahass-kiosk.service || true
  sleep 5
  if systemctl is-active --quiet ahass-kiosk.service 2>/dev/null; then
    ok "Unit layar aktif (belum diuji isi layar)."
  else
    warn "Unit layar tidak aktif. Jalankan nanti: sudo bash $APP_DIR/stb/screen-fix.sh"
  fi
fi

# ------------------------------------------------------------- 11. ringkasan
IP_ADDR="$(hostname -I 2>/dev/null | awk '{print $1}')"
PASSWORD_FILE="$DATA_DIR/ADMIN-PASSWORD.txt"

echo
echo "─────────────────────────────────────────────────────────────"
if [ "$SCREEN_RESULT" = "tampil" ]; then
  ok "Panel AHASS sudah TAMPIL di layar TV/monitor."
elif [ "$SCREEN_RESULT" = "gagal" ]; then
  warn "Panel jalan, tetapi layar belum menampilkan gambar. Lihat log di bawah."
else
  ok "Panel AHASS siap (layar belum diuji)."
fi
echo "  Panel tampilan : http://${IP_ADDR:-localhost}:$PORT/"
echo "  Halaman admin  : http://${IP_ADDR:-localhost}:$PORT/admin"
if [ -f "$PASSWORD_FILE" ]; then
  echo "  Password admin : $(grep -m1 'Password : ' "$PASSWORD_FILE" | sed 's/Password : //')"
  echo "                   ($PASSWORD_FILE)"
fi
# Layanan ulasan-google (port 3000) ikut dinyalakan bersama panel bila ada.
ULASAN_DIR_FOUND=""
for guess in /home/*/ulasan-google-main /home/*/ulasan-google /root/ulasan-google-main /opt/ulasan-google; do
  [ -d "$guess" ] && { ULASAN_DIR_FOUND="$guess"; break; }
done
if [ -n "$ULASAN_DIR_FOUND" ]; then
  bash "$APP_DIR/deploy/enable-ulasan-autostart.sh" --dir "$ULASAN_DIR_FOUND" \
    || warn "Layanan ulasan-google belum siap; aktifkan dari admin → Ulasan Google."
else
  warn "Folder ulasan-google tidak ditemukan — widget ulasan belum dijalankan otomatis."
  echo "        Pasang nanti: sudo bash $APP_DIR/deploy/enable-ulasan-autostart.sh --dir <folder>"
fi

echo
echo "  Layar  : systemctl status ahass-kiosk --no-pager"
echo "  Log    : sudo journalctl -u ahass-kiosk -n 40 --no-pager"
echo "  Uji    : sudo bash $APP_DIR/stb/smoke-test.sh"
echo "  Perbaiki layar lagi : sudo bash $APP_DIR/stb/screen-fix.sh"
echo "  Ulangi pemasangan   : sudo bash $APP_DIR/stb/install.sh --no-deps"
echo "─────────────────────────────────────────────────────────────"
echo
if [ "$SCREEN_RESULT" = "gagal" ]; then
  echo "Langkah berikutnya (kirim keluarannya ke pengembang):"
  echo "  1) sudo journalctl -u ahass-kiosk -n 40 --no-pager"
  echo "  2) grep -E '\\(EE\\)|Fatal' /var/log/Xorg.0.log | tail -20"
  exit 1
fi
echo "Langkah akhir: isi konfigurasi di halaman admin (DDMS, logo, ulasan, kotak 4-5)."
