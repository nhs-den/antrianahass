#!/usr/bin/env bash
#
# Pemasang Panel AHASS untuk Raspberry Pi 3 B+ (DietPi, microSD 16 GB).
#
#   sudo bash raspberry/install.sh                  # pasang / perbarui (mode otomatis)
#   sudo bash raspberry/install.sh --mode=desktop   # desktop LXDE + Chromium fullscreen
#   sudo bash raspberry/install.sh --mode=kiosk     # tty1 + xinit (tanpa desktop)
#   sudo bash raspberry/install.sh --no-deps        # lewati apt-get
#   sudo bash raspberry/install.sh --no-tweaks      # lewati sysctl/journald/logrotate
#   sudo bash raspberry/install.sh --resolution=1920x1080   # set mode HDMI
#   sudo bash raspberry/install.sh --dry-run        # tampilkan rencana saja
#
# Aman dijalankan berulang: konfigurasi di /var/lib/antrianahass tidak disentuh.
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/antrianahass}"
DATA_DIR="${DATA_DIR:-/var/lib/antrianahass}"
PORT="${PORT:-8080}"
PANEL_USER="${PANEL_USER:-ahass}"
KIOSK_USER="${KIOSK_USER:-}"
MODE="${MODE:-auto}"
INSTALL_DEPS=1
RESOLUTION=""
DRY=0
APPLY_TWEAKS=1

NODE_BIN="/usr/bin/node"

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PI_DIR="$SRC_DIR/raspberry"
LAUNCHER="/usr/local/bin/ahass-kiosk-desktop.sh"
FLAGS_TARGET="/etc/ahass/chromium-flags.conf"

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_info=$'\033[36m'
log()  { echo "${c_info}[ahass]${c_reset} $*"; }
ok()   { echo "${c_ok}[ ok ]${c_reset} $*"; }
warn() { echo "${c_warn}[warn]${c_reset} $*"; }
die()  { echo "${c_err}[fail]${c_reset} $*" >&2; exit 1; }

for arg in "$@"; do
  case "$arg" in
    --no-deps) INSTALL_DEPS=0 ;;
    --no-tweaks) APPLY_TWEAKS=0 ;;
    --mode=*) MODE="${arg#*=}" ;;
    --user=*) KIOSK_USER="${arg#*=}" ;;
    --port=*) PORT="${arg#*=}" ;;
    --resolution=*) RESOLUTION="${arg#*=}" ;;
    --dry-run) DRY=1 ;;
    -h|--help)
      awk 'NR>1 && NR<=20 && /^#/ {sub(/^# ?/, ""); print}' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *) die "Argumen tidak dikenal: $arg (lihat --help)" ;;
  esac
done

if [ ! -f "$SRC_DIR/server.js" ] || [ ! -f "$PI_DIR/units/ahass-kiosk.service" ]; then
  die "Sumber aplikasi tidak lengkap di $SRC_DIR.
     Jalankan dari dalam repo utuh, bukan dari folder raspberry/ saja:
       git clone https://github.com/nhs-den/antrianahass.git ~/antrianahass
       sudo bash ~/antrianahass/raspberry/install.sh"
fi

case "$MODE" in
  auto|desktop|kiosk) ;;
  *) die "Mode harus auto, desktop, atau kiosk (diberikan: $MODE)" ;;
esac

if [ "$DRY" != "1" ]; then
  [ "$(id -u)" = "0" ] || die "Jalankan sebagai root: sudo bash raspberry/install.sh"
fi

# --------------------------------------------------------------- 0. rencana
if [ "$DRY" = "1" ]; then
  log "RENCANA PEMASANGAN (dry-run, tidak ada yang diubah):"
  echo "    sumber        : $SRC_DIR"
  echo "    aplikasi      : $APP_DIR"
  echo "    data          : $DATA_DIR (tidak disentuh)"
  echo "    pengguna layar: ${KIOSK_USER:-<otomatis>}"
  echo "    mode layar    : $MODE"
  echo "    port          : $PORT"
  echo "    resolusi      : ${RESOLUTION:-<tidak diubah>}"
  echo "    paket         : nodejs chromium xserver-xorg xinit xauth x11-xserver-utils"
  echo "                    x11-utils x11-apps xserver-xorg-video-fbdev"
  echo "    kiosk         : window manager mini + xinit di tty1"
  echo "    izin          : chmod 755 $APP_DIR + a+rX (umask root DietPi = 077)"
  echo "    unit          : ahass-panel, ahass-kiosk, ahass-restart.timer"
  exit 0
fi

# ------------------------------------------------------------ 1. deteksi board
MODEL="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo 'tidak diketahui')"
ARCH="$(uname -m)"
MEM_MB="$(awk '/^MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo)"
DISK_FREE_MB="$(df -Pm / | awk 'NR==2 {print $4}')"

log "Model    : $MODEL"
log "Arsitektur: $ARCH"
log "RAM      : ${MEM_MB} MB"
log "Ruang /  : ${DISK_FREE_MB} MB bebas"

case "$MODEL" in
  *"Raspberry Pi 3"*) ok "Board terdeteksi Raspberry Pi 3." ;;
  *"Raspberry Pi"*) warn "Board Raspberry Pi lain; setelan memori di bawah dioptimalkan untuk 1 GB." ;;
  *) warn "Bukan Raspberry Pi (model: $MODEL); lanjutkan dengan hati-hati." ;;
esac

case "$ARCH" in
  aarch64|arm64) ok "OS 64-bit (arm64) - disarankan untuk DietPi di Pi 3 B+." ;;
  armv7l|armv6l)
    warn "OS 32-bit ($ARCH). Berjalan, tetapi Chromium 32-bit lebih boros memori."
    warn "DietPi arm64 lebih baik bila kartu mendukung."
    ;;
  *) warn "Arsitektur $ARCH belum diuji." ;;
esac

if [ "$MEM_MB" -lt 900 ]; then
  warn "RAM hanya ${MEM_MB} MB. Tutup layanan lain (mis. dietpi-cloudshell) agar Chromium tidak OOM."
fi
if [ "${DISK_FREE_MB:-0}" -lt 1500 ]; then
  warn "Ruang kosong < 1,5 GB. Chromium + Node butuh sekitar 700 MB saat pemasangan."
fi

# --------------------------------------------------------------- 2. paket apt
if [ "$INSTALL_DEPS" = "1" ]; then
  log "Memperbarui daftar paket…"
  apt-get update -qq || warn "apt-get update gagal, memakai cache lama."

  # xserver-xorg-video-fbdev WAJIB: di DietPi tanpa desktop, X tidak punya
  # driver sehingga berhenti dengan "(EE) no screens found".
  PACKAGES="ca-certificates curl fonts-dejavu-core logrotate xserver-xorg xinit xauth x11-xserver-utils x11-utils x11-apps xserver-xorg-video-fbdev"

  command -v unclutter >/dev/null 2>&1 || PACKAGES="$PACKAGES unclutter"
  command -v node >/dev/null 2>&1 || PACKAGES="$PACKAGES nodejs"
  if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
    PACKAGES="$PACKAGES chromium"
  fi

  log "Memasang paket: $PACKAGES"
  # shellcheck disable=SC2086
  if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $PACKAGES; then
    warn "Sebagian paket gagal dipasang. Minimal butuh: nodejs, curl, xserver-xorg, xinit."
    warn "Di DietPi, Chromium juga bisa dipasang dari: sudo dietpi-software"
  fi
fi

command -v node >/dev/null 2>&1 || die "Node.js tidak ada. Pasang: sudo apt-get install -y nodejs (minimal v18)."

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 18 ] || die "Node.js $(node -v) terlalu lama; butuh minimal v18."
NODE_BIN="$(command -v node || echo /usr/bin/node)"
ok "Node.js $(node -v) ($NODE_BIN)"

CHROMIUM_BIN=""
for candidate in chromium chromium-browser; do
  if command -v "$candidate" >/dev/null 2>&1; then CHROMIUM_BIN="$(command -v "$candidate")"; break; fi
done
if [ -n "$CHROMIUM_BIN" ]; then
  ok "Chromium: $CHROMIUM_BIN"
else
  warn "Chromium belum terpasang - layar kiosk tidak akan tampil."
  warn "Pasang: sudo apt-get install -y chromium  (atau lewat dietpi-software)"
fi

# ----------------------------------------------------------- 3. pengguna & dir
if ! id -u "$PANEL_USER" >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "$PANEL_USER"
  ok "Pengguna sistem $PANEL_USER dibuat."
fi

if [ -z "$KIOSK_USER" ]; then
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    KIOSK_USER="$SUDO_USER"
  elif id -u dietpi >/dev/null 2>&1; then
    KIOSK_USER="dietpi"
  else
    KIOSK_USER="$(awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd)"
  fi
fi
[ -n "$KIOSK_USER" ] || die "Tidak menemukan pengguna desktop. Tentukan manual: --user=NAMA"
id -u "$KIOSK_USER" >/dev/null 2>&1 || die "Pengguna $KIOSK_USER tidak ada."
KIOSK_HOME="$(getent passwd "$KIOSK_USER" | cut -d: -f6)"
[ -n "$KIOSK_HOME" ] || die "Direktori home $KIOSK_USER tidak ditemukan."

if [ "$MODE" = "auto" ]; then
  if [ -x /usr/bin/startlxde ] || [ -x /usr/bin/lxsession ] || command -v lxsession >/dev/null 2>&1; then
    MODE="desktop"
  else
    MODE="kiosk"
  fi
fi

log "Pengguna layar : $KIOSK_USER ($KIOSK_HOME)"
log "Mode layar    : $MODE"

if [ "$MODE" = "desktop" ]; then
  if ! command -v lxsession >/dev/null 2>&1 && [ ! -x /usr/bin/startlxde ]; then
    warn "Mode desktop dipilih tetapi LXDE tidak terdeteksi."
    warn "Pasang desktop: sudo dietpi-software  →  'Desktops' → LXDE,"
    warn "lalu set autostart: sudo dietpi-autostart  →  Automatic login (desktop)."
  fi
  if ! id -nG "$KIOSK_USER" | tr ' ' '\n' | grep -qx video; then
    usermod -aG video,audio,input,render "$KIOSK_USER" 2>/dev/null || true
    log "Pengguna $KIOSK_USER ditambahkan ke grup video/audio/input/render."
  fi
fi

# ------------------------------------------------------------- 4. salin app
# Penjaga: kalau skrip ini dipanggil dari salinan folder raspberry/ saja
# (bukan repo utuh), SRC_DIR akan menunjuk folder induk yang salah dan yang
# tersalin ke /opt bukan aplikasi — gejalanya "Cannot find module server.js"
# dan deploy/ hilang.
if [ ! -f "$SRC_DIR/server.js" ] || [ ! -f "$SRC_DIR/deploy/start-kiosk.sh" ]; then
  die "Sumber aplikasi tidak lengkap di $SRC_DIR (server.js / deploy/start-kiosk.sh tidak ada).
     Jalankan dari dalam repo utuh, mis.:
       git clone https://github.com/nhs-den/antrianahass.git ~/antrianahass
       sudo bash ~/antrianahass/raspberry/install.sh"
fi

log "Menyalin aplikasi ke $APP_DIR…"
mkdir -p "$APP_DIR"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete \
    --exclude '.git' --exclude 'node_modules' --exclude 'data' --exclude '.DS_Store' \
    "$SRC_DIR/" "$APP_DIR/"
else
  find "$APP_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  cp -a "$SRC_DIR/." "$APP_DIR/"
  rm -rf "$APP_DIR/.git" "$APP_DIR/data" "$APP_DIR/node_modules"
fi

mkdir -p "$DATA_DIR/uploads" "$DATA_DIR/chromium"
chown -R root:root "$APP_DIR"

# Permission harus dipaksa: umask root DietPi = 077, sehingga folder baru jadi
# 0700 milik root dan service yang berjalan sebagai 'ahass' gagal chdir
# (gejala: "status=200/CHDIR" berulang). chmod a+rX hanya menambah x pada
# folder & berkas yang sudah executable, jadi skrip tidak jadi executable
# untuk semua orang.
chmod 755 "$APP_DIR"
chmod -R a+rX "$APP_DIR"

chown -R "$PANEL_USER:$PANEL_USER" "$DATA_DIR"
chmod 750 "$DATA_DIR"
chown -R "$KIOSK_USER:$KIOSK_USER" "$DATA_DIR/chromium"
chmod +x "$APP_DIR/deploy/start-kiosk.sh" 2>/dev/null || true
ok "Aplikasi tersalin ($APP_DIR)."

# --------------------------------------------------------------- 5. systemd
log "Memasang layanan systemd…"
install -m 644 "$PI_DIR/units/ahass-panel.service" /etc/systemd/system/ahass-panel.service
install -m 644 "$PI_DIR/units/ahass-restart.service" /etc/systemd/system/ahass-restart.service
install -m 644 "$PI_DIR/units/ahass-restart.timer" /etc/systemd/system/ahass-restart.timer

sed -i "s#__KIOSK_HOME__#$KIOSK_HOME#g" /etc/systemd/system/ahass-restart.service

if [ "$PORT" != "8080" ]; then
  sed -i "s/^Environment=PORT=.*/Environment=PORT=$PORT/" /etc/systemd/system/ahass-panel.service
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
ok "Layanan ahass-panel + ahass-restart.timer terpasang."

# ------------------------------------------------------- 6. layar sesuai mode
CHROMIUM_FLAGS_LINE="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$PI_DIR/chromium-flags.conf" | tr '\n' ' ' | sed 's/  */ /g')"

if [ "$MODE" = "desktop" ]; then
  log "Menyiapkan mode desktop (autostart LXDE)…"

  install -m 755 "$PI_DIR/kiosk-desktop.sh" "$LAUNCHER"
  install -d -m 755 /etc/ahass
  install -m 644 "$PI_DIR/chromium-flags.conf" "$FLAGS_TARGET"

  AUTOSTART_DIR="$KIOSK_HOME/.config/lxsession/LXDE"
  AUTOSTART_FILE="$AUTOSTART_DIR/autostart"
  mkdir -p "$AUTOSTART_DIR"
  if [ ! -f "$AUTOSTART_FILE" ]; then
    if [ -f /etc/xdg/lxsession/LXDE/autostart ]; then
      cp /etc/xdg/lxsession/LXDE/autostart "$AUTOSTART_FILE"
    else
      : > "$AUTOSTART_FILE"
    fi
  fi
  # satu sumber autostart saja: hapus baris lama lalu tambahkan yang benar
  sed -i '\#ahass-kiosk-desktop\.sh#d' "$AUTOSTART_FILE"
  printf '@%s\n' "$LAUNCHER" >> "$AUTOSTART_FILE"
  chown "$KIOSK_USER:" "$AUTOSTART_FILE"
  chown "$KIOSK_USER:" "$AUTOSTART_DIR"

  # hindari peluncuran ganda lewat XDG autostart
  if [ -f "$KIOSK_HOME/.config/autostart/ahass-kiosk.desktop" ]; then
    rm -f "$KIOSK_HOME/.config/autostart/ahass-kiosk.desktop"
    warn "Entri XDG autostart lama dihapus (penyebab layar terbuka dua kali)."
  fi

  # unit kiosk systemd tidak dipakai pada mode desktop
  if systemctl list-unit-files 2>/dev/null | grep -q '^ahass-kiosk\.service'; then
    systemctl disable --now ahass-kiosk.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/ahass-kiosk.service
    systemctl daemon-reload
  fi

  ok "Launcher: $LAUNCHER"
  ok "Flag Chromium: $FLAGS_TARGET"
  ok "Autostart LXDE: $AUTOSTART_FILE"
else
  log "Menyiapkan mode kiosk (tty1 + xinit)…"

  # Window manager mini. Tanpa WM, Chromium mengabaikan --kiosk /
  # --start-fullscreen dan memakai ukuran jendela tersimpan di profil
  # (gejala: jendela 945x1060 di layar 1920x1080, layout jadi bertumpuk).
  WM_BIN=""
  if ! command -v matchbox-window-manager >/dev/null 2>&1 \
     && ! command -v openbox >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends matchbox-window-manager >/dev/null 2>&1 \
      || DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openbox >/dev/null 2>&1 \
      || warn "Window manager tidak bisa dipasang; fullscreen mungkin tidak sempurna."
  fi
  for cand in matchbox-window-manager openbox fluxbox; do
    command -v "$cand" >/dev/null 2>&1 && { WM_BIN="$cand"; break; }
  done

  install -m 644 "$PI_DIR/units/ahass-kiosk.service" /etc/systemd/system/ahass-kiosk.service
  sed -i "s#__KIOSK_USER__#$KIOSK_USER#g" /etc/systemd/system/ahass-kiosk.service
  sed -i "s#__CHROMIUM_FLAGS__#$CHROMIUM_FLAGS_LINE#g" /etc/systemd/system/ahass-kiosk.service
  # Profil Chromium di home pengguna kiosk: folder data tetap boleh 750 dan
  # tidak perlu dilonggarkan hanya agar Chromium bisa menulis profil.
  sed -i "s#^Environment=AHASS_PROFILE_DIR=.*#Environment=AHASS_PROFILE_DIR=$KIOSK_HOME/.config/ahass-kiosk#" \
    /etc/systemd/system/ahass-kiosk.service
  if [ "$PORT" != "8080" ]; then
    sed -i "s#^Environment=AHASS_URL=.*#Environment=AHASS_URL=http://127.0.0.1:$PORT/#" /etc/systemd/system/ahass-kiosk.service
  fi

  # Skrip klien kiosk disalin ke /usr/local/bin supaya tidak ikut berubah/hilang
  # setiap kali folder /opt diperbarui.
  install -m 755 "$APP_DIR/deploy/start-kiosk.sh" /usr/local/bin/ahass-start-kiosk.sh
  if [ -n "$WM_BIN" ]; then
    cat > /usr/local/bin/ahass-kiosk-boot.sh <<BOOTEOF
#!/bin/sh
# Dibuat raspberry/install.sh: jalankan window manager mini, lalu kiosk.
$WM_BIN $([ "$WM_BIN" = "matchbox-window-manager" ] && echo "-use_titlebar no") >/dev/null 2>&1 &
sleep 1
exec /usr/local/bin/ahass-start-kiosk.sh
BOOTEOF
    chmod 755 /usr/local/bin/ahass-kiosk-boot.sh
    sed -i "s#^ExecStart=.*#ExecStart=/usr/bin/xinit /usr/local/bin/ahass-kiosk-boot.sh -- :0 vt1 -nolisten tcp -nocursor#" \
      /etc/systemd/system/ahass-kiosk.service
  else
    sed -i "s#^ExecStart=.*#ExecStart=/usr/bin/xinit /usr/local/bin/ahass-start-kiosk.sh -- :0 vt1 -nolisten tcp -nocursor#" \
      /etc/systemd/system/ahass-kiosk.service
  fi

  # Grup tambahan WAJIB: Group= mengganti grup utama sehingga tanpa
  # SupplementaryGroups, proses tidak bisa membuka /dev/fb0 (root:video 660).
  mkdir -p "/etc/systemd/system/ahass-kiosk.service.d"
  cat > "/etc/systemd/system/ahass-kiosk.service.d/10-groups.conf" <<'GRPEOF'
[Service]
SupplementaryGroups=video render input audio
GRPEOF

  # Driver fbdev: pastikan X punya sesuatu untuk menggambar bila /dev/dri
  # tidak tersedia (kernel legacy framebuffer seperti di DietPi).
  if [ ! -e /dev/dri/card0 ]; then
    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/xorg.conf.d/99-ahass-fbdev.conf <<'FBEOF'
# Dibuat raspberry/install.sh: pakai framebuffer legacy bila KMS tidak aktif.
Section "Device"
    Identifier "AHASS FBDEV"
    Driver     "fbdev"
    Option     "fbdev" "/dev/fb0"
EndSection
FBEOF
  fi

  # jangan biarkan autostart desktop ikut menjalankan launcher kedua
  AUTOSTART_FILE="$KIOSK_HOME/.config/lxsession/LXDE/autostart"
  if [ -f "$AUTOSTART_FILE" ]; then
    sed -i '\#ahass-kiosk-desktop\.sh#d' "$AUTOSTART_FILE"
  fi

  install -d -m 755 -o "$KIOSK_USER" -g "$KIOSK_USER" "$KIOSK_HOME/.config/ahass-kiosk" 2>/dev/null || true

  systemctl daemon-reload
  systemctl enable ahass-kiosk.service >/dev/null 2>&1
  ok "Unit ahass-kiosk terpasang${WM_BIN:+ (WM: $WM_BIN)} (aktif pada boot berikutnya)."
fi

# ------------------------------------------------- 6b. resolusi HDMI (opsional)
if [ -n "$RESOLUTION" ]; then
  RW="${RESOLUTION%x*}"
  RH="${RESOLUTION#*x}"
  log "Menyetel resolusi HDMI ke ${RW}x${RH}…"
  RESULT="$(node -e "
    const s = require('$APP_DIR/lib/screen');
    try {
      const r = s.apply({ width: $RW, height: $RH });
      console.log('ok:' + r.changes.join(', '));
    } catch (e) { console.log('err:' + e.message); }
  " 2>/dev/null || echo 'err:node gagal')"
  case "$RESULT" in
    ok:*) ok "Resolusi diset (${RESULT#ok:}). Reboot untuk menerapkan." ;;
    *) warn "Resolusi tidak bisa diset (${RESULT#err:}). Atur lewat dietpi-config." ;;
  esac
fi

# --------------------------------------------------------------- 7. tweak OS
if [ "$APPLY_TWEAKS" = "1" ]; then
  log "Menerapkan tweak kecil untuk microSD 16 GB / RAM 1 GB…"

  install -m 644 "$PI_DIR/sysctl-ahass-pi.conf" /etc/sysctl.d/99-ahass-pi.conf
  sysctl --system >/dev/null 2>&1 || warn "sysctl --system gagal; nilai berlaku setelah reboot."

  install -d -m 755 /etc/systemd/journald.conf.d
  install -m 644 "$PI_DIR/journald-ahass-small.conf" /etc/systemd/journald.conf.d/ahass-small.conf
  systemctl restart systemd-journald >/dev/null 2>&1 || warn "systemd-journald gagal di-restart."

  sed "s#__KIOSK_USER__#$KIOSK_USER#g" "$PI_DIR/logrotate-ahass.conf" > /etc/logrotate.d/ahass-kiosk
  chmod 644 /etc/logrotate.d/ahass-kiosk

  ok "Tweak terpasang (sysctl, journald 64 MB, logrotate kiosk)."
fi

# --------------------------------------------------------------- 8. jalankan
log "Menjalankan server panel…"
systemctl restart ahass-panel.service

HEALTH_OK=0
i=0
while [ "$i" -lt 25 ]; do
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
  warn "Panel belum menjawab. Periksa: journalctl -u ahass-panel -n 40 --no-pager"
fi

if [ "$MODE" = "kiosk" ] && [ -n "$CHROMIUM_BIN" ]; then
  warn "Mode kiosk butuh reboot agar layar tty1 diambil alih."
fi

# ------------------------------------------------------------- 9. ringkasan
AUTOSTART_INDEX=""
for f in /boot/dietpi/.dietpi-autostart_index /boot/firmware/dietpi/.dietpi-autostart_index; do
  if [ -r "$f" ]; then
    AUTOSTART_INDEX="$(tr -dc '0-9' < "$f")"
    break
  fi
done

IP_ADDR="$(hostname -I 2>/dev/null | awk '{print $1}')"
PASSWORD_FILE="$DATA_DIR/ADMIN-PASSWORD.txt"

echo
echo "─────────────────────────────────────────────────────────────"
ok "Panel AHASS siap di Raspberry Pi."
echo "  Panel tampilan : http://${IP_ADDR:-localhost}:$PORT/"
echo "  Halaman admin  : http://${IP_ADDR:-localhost}:$PORT/admin"
if [ -f "$PASSWORD_FILE" ]; then
  echo "  Password admin : $(grep -m1 'Password : ' "$PASSWORD_FILE" | sed 's/Password : //')"
  echo "                   (tersimpan di $PASSWORD_FILE)"
else
  echo "  Password admin : password yang sudah Anda tetapkan"
fi
echo
if [ "$MODE" = "desktop" ]; then
  echo "  Mode layar     : desktop LXDE + Chromium fullscreen"
  echo "  Wajib          : sudo dietpi-autostart  →  'Automatic login' (desktop)"
  echo "                   (biasanya bernomor 2; bukan Manual login)"
  if [ -n "$AUTOSTART_INDEX" ] && [ "$AUTOSTART_INDEX" != "2" ]; then
    warn "Autostart DietPi saat ini = $AUTOSTART_INDEX, layar tidak akan muncul otomatis."
  fi
  echo "  Log launcher   : tail -f $KIOSK_HOME/ahass-kiosk-desktop.log"
else
  echo "  Mode layar     : kiosk tty1 (xinit, tanpa desktop)"
  echo "  Wajib          : sudo dietpi-autostart  →  'Manual login' (biasanya 0)"
  if [ "$AUTOSTART_INDEX" = "2" ]; then
    warn "Autostart DietPi = 2 (desktop) akan berebut layar dengan unit kiosk."
    warn "Ubah ke Manual login, atau pakai ulang: sudo bash $APP_DIR/raspberry/install.sh --mode=desktop"
  fi
  echo "  Log kiosk      : sudo journalctl -u ahass-kiosk -f"
fi
echo
echo "  Status : systemctl status ahass-panel ahass-kiosk 2>/dev/null"
echo "  Ulangi : sudo bash $APP_DIR/raspberry/install.sh --no-deps"
echo "  Hapus  : sudo bash $APP_DIR/raspberry/uninstall.sh"
echo "─────────────────────────────────────────────────────────────"
echo
echo "Reboot sekali untuk memastikan layar muncul otomatis: sudo reboot"
