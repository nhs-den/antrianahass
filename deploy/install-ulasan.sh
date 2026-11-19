#!/usr/bin/env bash
#
# Memasang aplikasi ulasan-google sebagai layanan systemd di port 3000,
# supaya widget di kotak ke-3 selalu hidup saat perangkat menyala.
#
#   sudo bash deploy/install-ulasan.sh --dir /home/den/ulasan-google-main
#   sudo bash deploy/install-ulasan.sh --dir ~/ulasan-google-main --dry-run
#
# Skrip mendeteksi jenis aplikasi (Node / PHP / Python / start.sh),
# memasang dependensi bila perlu, lalu membuat ulasan-google.service.
#
set -euo pipefail

APP_SRC=""
PORT="${ULASAN_PORT:-3000}"
SERVICE_USER=""
DRY_RUN=0
INSTALL_DEPS=1
UNIT=/etc/systemd/system/ulasan-google.service

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) APP_SRC="${2:-}"; shift 2 ;;
    --dir=*) APP_SRC="${1#*=}"; shift ;;
    --port) PORT="${2:-3000}"; shift 2 ;;
    --user) SERVICE_USER="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-deps) INSTALL_DEPS=0; shift ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Argumen tidak dikenal: $1" >&2; exit 1 ;;
  esac
done

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_info=$'\033[36m'
log()  { echo "${c_info}[ulasan]${c_reset} $*"; }
ok()   { echo "${c_ok}[ ok ]${c_reset} $*"; }
warn() { echo "${c_warn}[warn]${c_reset} $*"; }
die()  { echo "${c_err}[fail]${c_reset} $*" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = "1" ]; then echo "    (dry-run) $*"; else "$@"; fi; }

if [ "$DRY_RUN" != "1" ]; then
  [ "$(id -u)" = "0" ] || die "Jalankan sebagai root: sudo bash deploy/install-ulasan.sh --dir <folder>"
fi

# --------------------------------------------------------- cari foldernya
if [ -z "$APP_SRC" ]; then
  for guess in "$HOME/ulasan-google-main" /home/*/ulasan-google-main "$HOME/ulasan-google" /opt/ulasan-google /home/*/ulasan-google; do
    if [ -d "$guess" ]; then APP_SRC="$guess"; break; fi
  done
fi
[ -n "$APP_SRC" ] && [ -d "$APP_SRC" ] || die "Folder aplikasi ulasan-google tidak ditemukan. Gunakan --dir <folder>."
APP_SRC="$(cd "$APP_SRC" && pwd)"
log "Folder aplikasi: $APP_SRC"
log "Port            : $PORT"

# ------------------------------------------------------------- deteksi
EXEC_START=""
NEED_DEPS=""

if [ -f "$APP_SRC/package.json" ]; then
  START_SCRIPT="$(node -p "try{require('$APP_SRC/package.json').scripts.start||''}catch(e){''}" 2>/dev/null || true)"
  MAIN_FIELD="$(node -p "try{require('$APP_SRC/package.json').main||''}catch(e){''}" 2>/dev/null || true)"
  ENTRY=""

  # "node server.js" / "node ./src/index.js"
  if [[ "$START_SCRIPT" =~ ^node[[:space:]]+([^[:space:]]+) ]]; then
    ENTRY="${BASH_REMATCH[1]}"
  fi
  if [ -z "$ENTRY" ]; then
    for candidate in "$MAIN_FIELD" server.js app.js index.js main.js src/server.js src/index.js src/app.js bin/www; do
      [ -n "$candidate" ] && [ -f "$APP_SRC/$candidate" ] && { ENTRY="$candidate"; break; }
    done
  fi

  if [ -n "$ENTRY" ]; then
    EXEC_START="/usr/bin/node $ENTRY"
  elif [ -n "$START_SCRIPT" ]; then
    EXEC_START="/usr/bin/npm start"
  else
    die "package.json tidak punya 'start' maupun berkas entry yang dikenali."
  fi
  [ -d "$APP_SRC/node_modules" ] || NEED_DEPS="npm"
  log "Terdeteksi aplikasi Node.js (entry: ${ENTRY:-npm start})"

elif [ -f "$APP_SRC/index.php" ] || [ -f "$APP_SRC/public/index.php" ]; then
  DOCROOT="$APP_SRC"
  [ -d "$APP_SRC/public" ] && DOCROOT="$APP_SRC/public"
  EXEC_START="/usr/bin/php -S 0.0.0.0:$PORT -t $DOCROOT"
  command -v php >/dev/null 2>&1 || NEED_DEPS="php"
  log "Terdeteksi aplikasi PHP (docroot: $DOCROOT)"

elif [ -f "$APP_SRC/app.py" ] || [ -f "$APP_SRC/main.py" ]; then
  ENTRY_FILE="app.py"; [ -f "$APP_SRC/app.py" ] || ENTRY_FILE="main.py"
  command -v python3 >/dev/null 2>&1 || die "python3 tidak ditemukan."
  EXEC_START="/usr/bin/python3 $ENTRY_FILE"
  [ -f "$APP_SRC/requirements.txt" ] && NEED_DEPS="pip"
  log "Terdeteksi aplikasi Python ($ENTRY_FILE)"

elif [ -f "$APP_SRC/start.sh" ]; then
  EXEC_START="/bin/bash $APP_SRC/start.sh"
  log "Terdeteksi start.sh"

else
  warn "Isi folder tidak dikenali:"
  ls -1 "$APP_SRC" | sed 's/^/    - /'
  die "Kirim daftar berkas di atas agar unit systemd bisa dibuatkan manual."
fi

# --------------------------------------------------------- pengguna service
if [ -z "$SERVICE_USER" ]; then
  OWNER="$(stat -c '%U' "$APP_SRC")"
  if [ "$OWNER" = "root" ]; then
    SERVICE_USER="ulasan"
    if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
      log "Membuat pengguna sistem 'ulasan'…"
      run useradd --system --no-create-home --shell /usr/sbin/nologin ulasan
    fi
    run chown -R ulasan:ulasan "$APP_SRC"
  else
    SERVICE_USER="$OWNER"
  fi
fi
log "Service berjalan sebagai: $SERVICE_USER"

# ------------------------------------------------------------ dependensi
if [ "$NEED_DEPS" = "npm" ] && [ "$INSTALL_DEPS" = "1" ]; then
  log "Memasang dependensi Node (npm install --omit=dev)…"
  ( cd "$APP_SRC" && run npm install --omit=dev --no-audit --no-fund ) || warn "npm install gagal — periksa koneksi internet."
elif [ "$NEED_DEPS" = "pip" ] && [ "$INSTALL_DEPS" = "1" ]; then
  log "Memasang dependensi Python…"
  ( cd "$APP_SRC" && run python3 -m pip install -r requirements.txt --break-system-packages ) || warn "pip install gagal."
elif [ "$NEED_DEPS" = "php" ]; then
  warn "PHP belum terpasang: apt-get install -y php-cli"
fi

# --------------------------------------------------------------- unit
log "Menulis $UNIT"
if [ "$DRY_RUN" = "1" ]; then
  cat <<EOF
    (dry-run) isi unit:
    [Service]
    User=$SERVICE_USER
    WorkingDirectory=$APP_SRC
    Environment=PORT=$PORT
    ExecStart=$EXEC_START
EOF
else
  cat > "$UNIT" <<EOF
[Unit]
Description=Service ulasan Google (widget panel AHASS)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$APP_SRC
Environment=NODE_ENV=production
Environment=PORT=$PORT
ExecStart=$EXEC_START
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ulasan-google

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable ulasan-google.service >/dev/null 2>&1 || true
  systemctl restart ulasan-google.service
  sleep 3
fi

# ------------------------------------------------------------- verifikasi
echo
if [ "$DRY_RUN" = "1" ]; then
  ok "Dry-run selesai. Jalankan tanpa --dry-run untuk memasang."
  exit 0
fi

if systemctl is-active --quiet ulasan-google.service; then
  ok "Layanan aktif."
else
  warn "Layanan gagal aktif. 20 baris log terakhir:"
  journalctl -u ulasan-google -n 20 --no-pager || true
fi

CODE="$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:$PORT/loader.js" || echo 000)"
if [ "$CODE" = "200" ]; then
  ok "http://127.0.0.1:$PORT/loader.js → 200 (siap dipakai panel)"
else
  warn "http://127.0.0.1:$PORT/loader.js → $CODE"
  warn "Aplikasi mungkin memakai path/port berbeda. Cek log: journalctl -u ulasan-google -f"
fi

echo
echo "  Panel memakai widget ini lewat admin → Ulasan Google → mode snippet"
echo "  (port $PORT, path /loader.js, query kiosk=1)."
echo
