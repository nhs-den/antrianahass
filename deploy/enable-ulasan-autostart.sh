#!/usr/bin/env bash
#
# Memastikan layanan ulasan-google (port 3000) menyala berbarengan dengan panel.
#
#   sudo bash deploy/enable-ulasan-autostart.sh                 # cari folder otomatis
#   sudo bash deploy/enable-ulasan-autostart.sh --dir /home/den/ulasan-google-main
#   sudo bash deploy/enable-ulasan-autostart.sh --dry-run
#
# Dilengkapi: unit systemd ulasan-google.service + drop-in pada ahass-panel
# (Wants=/After=) supaya saat boot keduanya dijalankan berdampingan tapi
# kegagalan widget ulasan TIDAK pernah menghalangi panel antrian.
# Untuk Raspberry Pi/STB, nama unit panelnya ahass-panel.service juga, jadi
# skrip ini bisa dipakai apa adanya.
#
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_APP="${ULASAN_DIR:-}"
PANEL_UNIT="${PANEL_UNIT:-ahass-panel.service}"
PORT="${ULASAN_PORT:-3000}"
DRY_RUN=0
RUN_FILE=/var/lib/antrianahass/ulasan-google.cmd

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) TARGET_APP="${2:-}"; shift 2 ;;
    --dir=*) TARGET_APP="${1#*=}"; shift ;;
    --port) PORT="${2:-3000}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Argumen tidak dikenal: $1" >&2; exit 1 ;;
  esac
done

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_info=$'\033[36m'
log()  { echo "${c_info}[ulasan]${c_reset} $*"; }
ok()   { echo "${c_ok}[ ok ]${c_reset} $*"; }
warn() { echo "${c_warn}[warn]${c_reset} $*"; }
die()  { echo "${c_err}[fail]${c_reset} $*" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = "1" ]; then echo "    (dry-run) $*"; else "$@" ; fi; }

[ "$DRY_RUN" = "1" ] || [ "$(id -u)" = "0" ] || die "Jalankan sebagai root: sudo bash deploy/enable-ulasan-autostart.sh"

# ------------------------------------------------------------ cari folder
if [ -z "$TARGET_APP" ]; then
  for guess in /home/*/ulasan-google-main /home/*/ulasan-google /root/ulasan-google-main \
               /opt/ulasan-google /opt/ulasan-google-main /srv/ulasan-google; do
    [ -d "$guess" ] && { TARGET_APP="$guess"; break; }
  done
fi
if [ -z "$TARGET_APP" ] || [ ! -d "$TARGET_APP" ]; then
  warn "Folder aplikasi ulasan-google tidak ditemukan."
  echo "  Cari manual:  ls -d /home/*/ulasan*"
  echo "  Lalu ulangi:  sudo bash $APP_DIR/deploy/enable-ulasan-autostart.sh --dir <folder>"
  echo
  echo "  Tanpa folder, layanan tetap bisa dijalankan dari halaman admin"
  echo "  (Ulasan Google → Layanan ulasan → Jalankan sekarang)."
  exit 1
fi
TARGET_APP="$(cd "$TARGET_APP" && pwd)"
log "Folder aplikasi: $TARGET_APP"

# ------------------------------------------------------- pasang unit utama
if [ ! -f /etc/systemd/system/ulasan-google.service ]; then
  log "Memasang unit ulasan-google.service lewat deploy/install-ulasan.sh…"
  EXTRA=""
  [ "$DRY_RUN" = "1" ] && EXTRA="--dry-run"
  # shellcheck disable=SC2086
  run bash "$APP_DIR/deploy/install-ulasan.sh" --dir "$TARGET_APP" --port "$PORT" --no-deps $EXTRA
else
  log "Unit ulasan-google.service sudah ada, dilewati (hapus dulu bila ingin dibuat ulang)."
fi

# ----------------------------------- catat perintah start untuk panel (fallback)
SERVICE_USER="$(systemctl show -p User --value ulasan-google.service 2>/dev/null || true)"
[ -n "$SERVICE_USER" ] || SERVICE_USER="$(stat -c '%U' "$TARGET_APP")"
EXEC_LINE="$(systemctl show -p ExecStart --value ulasan-google.service 2>/dev/null | sed 's/^.*argv\[\]=//; s/ ; ignore_errors.*$//' || true)"
if [ -n "$EXEC_LINE" ]; then
  log "Menyimpan perintah start ke $RUN_FILE (dipakai panel bila systemd tidak tersedia)"
  if [ "$DRY_RUN" = "1" ]; then
    echo "    (dry-run) echo 'cd $TARGET_APP && PORT=$PORT $EXEC_LINE' > $RUN_FILE"
  else
    mkdir -p "$(dirname "$RUN_FILE")"
    printf 'cd %s && PORT=%s %s\n' "$TARGET_APP" "$PORT" "$EXEC_LINE" > "$RUN_FILE"
    chmod 644 "$RUN_FILE"
  fi
fi

# ----------------------------------------- drop-in: panel Wants= layanan ulasan
DROPIN_DIR="/etc/systemd/system/$PANEL_UNIT.d"
log "Menulis drop-in $DROPIN_DIR/ulasan.conf"
if [ "$DRY_RUN" = "1" ]; then
  echo "    (dry-run) Wants=ulasan-google.service / After=ulasan-google.service"
else
  mkdir -p "$DROPIN_DIR"
  cat > "$DROPIN_DIR/ulasan.conf" <<EOF
# Ditambahkan deploy/enable-ulasan-autostart.sh
# Panel dan widget ulasan menyala berbarengan; keduanya independen supaya
# gangguan pada widget ulasan tidak menghalangi panel antrian.
Wants=ulasan-google.service
After=ulasan-google.service
EOF
  systemctl daemon-reload
  systemctl enable ulasan-google.service >/dev/null 2>&1 || true
  systemctl restart ulasan-google.service || warn "ulasan-google gagal dijalankan, cek: journalctl -u ulasan-google -n 30"
fi

echo
if [ "$DRY_RUN" = "1" ]; then
  ok "Dry-run selesai. Jalankan tanpa --dry-run untuk menerapkan."
  exit 0
fi

sleep 2
if systemctl is-active --quiet ulasan-google.service; then
  ok "Layanan ulasan aktif di port $PORT."
else
  warn "Layanan belum aktif. 20 baris log terakhir:"
  journalctl -u ulasan-google -n 20 --no-pager || true
fi

CODE="$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:$PORT/loader.js" || echo 000)"
if [ "$CODE" = "200" ]; then
  ok "http://127.0.0.1:$PORT/loader.js → 200 (widget siap dipakai panel)"
else
  warn "http://127.0.0.1:$PORT/loader.js → $CODE (periksa path/port aplikasinya)"
fi

echo
echo "  Panel dan widget ulasan sekarang menyala bersamaan:"
echo "    systemctl status ahass-panel ulasan-google"
echo "  Panel juga bisa menyalakan/menghentikan ulasan dari admin →"
echo "    Ulasan Google → Layanan ulasan (port $PORT)."
echo
