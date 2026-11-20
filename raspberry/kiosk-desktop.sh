#!/bin/sh
# Launcher kiosk mode-desktop untuk Panel AHASS (Raspberry Pi / DietPi + LXDE).
#
# Dipanggil dari autostart LXDE:
#   @/usr/local/bin/ahass-kiosk-desktop.sh
#
# Perilaku:
#   1. Menunggu panel Node (port 8080) benar-benar menjawab, baru membuka
#      Chromium. Ini mencegah layar putih "This site can't be reached" saat
#      boot, karena Chromium tidak pernah me-reload halaman error sendiri.
#   2. Watchdog: bila panel gagal 2x berturut-turut, Chromium di-restart.
#   3. Semua aktivitas dicatat ke ~/ahass-kiosk-desktop.log (di-rotate oleh
#      logrotate, lihat raspberry/logrotate-ahass.conf).
#
# Variabel lingkungan yang bisa diubah:
#   AHASS_URL               default http://127.0.0.1:8080/
#   AHASS_PROFILE_DIR       default $HOME/.config/ahass-kiosk
#   AHASS_CHROMIUM_FLAGS_FILE default /etc/ahass/chromium-flags.conf
#   AHASS_KIOSK_LOG         default $HOME/ahass-kiosk-desktop.log
#   AHASS_WAIT_SECONDS      default 180 (batas tunggu panel)
#   AHASS_WATCHDOG_SECONDS  default 20
set -u

URL="${AHASS_URL:-http://127.0.0.1:8080/}"
HEALTH="${URL%/}/__ahass/api/health"
PROFILE="${AHASS_PROFILE_DIR:-$HOME/.config/ahass-kiosk}"
FLAGS_FILE="${AHASS_CHROMIUM_FLAGS_FILE:-/etc/ahass/chromium-flags.conf}"
LOG="${AHASS_KIOSK_LOG:-$HOME/ahass-kiosk-desktop.log}"
WAIT_MAX="${AHASS_WAIT_SECONDS:-180}"
CHECK_EVERY="${AHASS_WATCHDOG_SECONDS:-20}"

# Log dibuka paling awal supaya kegagalan apa pun tetap terekam.
exec >>"$LOG" 2>&1
echo "=== $(date '+%F %T') launcher dipanggil (pid $$, user $(id -un)) ==="

# Guard single-instance: kalau autostart terpanggil dua kali, yang kedua keluar.
if command -v flock >/dev/null 2>&1; then
  exec 9>/tmp/ahass-kiosk-desktop.lock
  if ! flock -n 9; then
    echo "$(date '+%F %T') instance lain masih berjalan, keluar"
    exit 0
  fi
fi

# Layar jangan tidur.
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

# Sembunyikan kursor.
if command -v unclutter >/dev/null 2>&1; then
  unclutter -idle 1 -root >/dev/null 2>&1 &
fi

panel_ready() {
  if command -v curl >/dev/null 2>&1; then
    curl -fs -m 3 -o /dev/null "$HEALTH"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 3 -O /dev/null "$HEALTH"
  else
    # Tanpa curl/wget: beri waktu server menyala, jangan gagal.
    sleep 1
    return 0
  fi
}

read_flags() {
  [ -r "$FLAGS_FILE" ] || return 0
  sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$FLAGS_FILE" | tr '\n' ' '
}

CHROME=""
for candidate in chromium chromium-browser google-chrome-stable google-chrome; do
  if command -v "$candidate" >/dev/null 2>&1; then
    CHROME="$candidate"
    break
  fi
done

if [ -z "$CHROME" ]; then
  echo "$(date '+%F %T') Chromium tidak ditemukan di PATH=$PATH"
  echo "Pasang dengan: sudo apt-get install -y chromium"
  echo "atau: sudo dietpi-software  (cari 'Chromium')"
  exit 1
fi

mkdir -p "$PROFILE" 2>/dev/null || true
echo "$(date '+%F %T') pakai $CHROME, profil $PROFILE"

while true; do
  # --- 1. tunggu panel siap (bukan tidur tetap) ---
  waited=0
  until panel_ready; do
    waited=$((waited + 2))
    if [ "$waited" -ge "$WAIT_MAX" ]; then
      echo "$(date '+%F %T') panel belum siap setelah ${WAIT_MAX}s, tetap buka Chromium"
      break
    fi
    sleep 2
  done
  echo "$(date '+%F %T') panel siap (tunggu ${waited}s), buka Chromium"

  # --- 2. jalankan Chromium fullscreen ---
  # 9>&- : jangan wariskan file descriptor lock ke proses anak, supaya lock
  # tidak tertahan setelah launcher ini berhenti.
  # shellcheck disable=SC2046,SC2086
  "$CHROME" --kiosk --user-data-dir="$PROFILE" $(read_flags) "$URL" 9>&- &
  CPID=$!

  # --- 3. watchdog ---
  miss=0
  while kill -0 "$CPID" 2>/dev/null; do
    sleep "$CHECK_EVERY"
    if panel_ready; then
      miss=0
    else
      miss=$((miss + 1))
    fi
    if [ "$miss" -ge 2 ]; then
      echo "$(date '+%F %T') panel tidak merespons, restart Chromium"
      pkill -f "user-data-dir=$PROFILE" 2>/dev/null || true
      break
    fi
  done

  wait "$CPID" 2>/dev/null || true
  pkill -f "user-data-dir=$PROFILE" 2>/dev/null || true
  sleep 3
done
