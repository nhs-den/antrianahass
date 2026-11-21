#!/bin/sh
# Menjalankan Chromium kiosk di STB untuk panel yang dilayani PC.
# Dipanggil oleh ahass-pc-kiosk.service lewat xinit.
#
# Alamat panel dibaca dari (urutan prioritas):
#   1. AHASS_PANEL_URL  (systemd Environment)
#   2. /etc/ahass-client/panel-url
#   3. http://127.0.0.1:8080/  (hanya untuk uji lokal)
#
# Skrip ini sengaja dibuat mandiri: TIDAK memakai deploy/start-kiosk.sh,
# karena di STB-client folder deploy/ tidak ikut dipasang.

set -e

exec >>/var/log/ahass-kiosk-client.log 2>&1
# Jangan biarkan log tumbuh tanpa batas (STB hidup 24/7, SD card terbatas).
if [ -f /var/log/ahass-kiosk-client.log ] && [ "$(wc -c </var/log/ahass-kiosk-client.log)" -gt 1048576 ]; then
  tail -c 300000 /var/log/ahass-kiosk-client.log > /var/log/ahass-kiosk-client.log.tmp 2>/dev/null \
    && mv /var/log/ahass-kiosk-client.log.tmp /var/log/ahass-kiosk-client.log
fi

export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/ahass-pc-kiosk}"
export HOME="${HOME:-/home/$(id -un)}"
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true

URL="${AHASS_PANEL_URL:-}"
if [ -z "$URL" ] && [ -r /etc/ahass-client/panel-url ]; then
  URL="$(head -1 /etc/ahass-client/panel-url)"
fi
[ -n "$URL" ] || URL="http://127.0.0.1:8080/"

PROFILE_DIR="${AHASS_PROFILE_DIR:-$HOME/.config/ahass-kiosk}"

# Tunggu X siap (maks 10 detik) supaya Chromium tidak gagal konek.
X_SCREEN="${DISPLAY#*:}"
X_SCREEN="${X_SCREEN%%.*}"
SOCKET="/tmp/.X11-unix/X${X_SCREEN}"
i=0
while [ ! -S "$SOCKET" ] && [ "$i" -lt 20 ]; do
  sleep 0.5
  i=$((i + 1))
done
[ -S "$SOCKET" ] || echo "X server belum siap pada $DISPLAY." >&2

mkdir -p "$PROFILE_DIR" 2>/dev/null || true

# Layar tidak boleh tidur / blank pada panel 24 jam.
if command -v xset >/dev/null 2>&1; then
  xset s off 2>/dev/null || true
  xset -dpms 2>/dev/null || true
  xset s noblank 2>/dev/null || true
fi
if command -v xsetroot >/dev/null 2>&1; then
  xsetroot -solid '#000000' 2>/dev/null || true
fi
if command -v unclutter >/dev/null 2>&1; then
  unclutter -idle 1 -root >/dev/null 2>&1 &
fi

CHROME=""
for candidate in chromium chromium-browser google-chrome google-chrome-stable chrome; do
  if command -v "$candidate" >/dev/null 2>&1; then
    CHROME="$(command -v "$candidate")"
    break
  fi
done
if [ -z "$CHROME" ]; then
  echo "Chromium tidak ditemukan. Pasang: apt-get install -y chromium" >&2
  exit 1
fi

BASE_FLAGS="--kiosk --no-first-run --no-default-browser-check --noerrdialogs \
--disable-infobars --disable-session-crashed-bubble --disable-translate --disable-sync \
--disable-background-networking --disable-component-update --disable-default-apps \
--disable-extensions --disable-pinch --overscroll-history-navigation=0 \
--disable-features=Translate,MediaRouter,OptimizationHints,CalculateNativeWinOcclusion,InterestFeedContentSuggestions \
--password-store=basic --use-mock-keychain --autoplay-policy=no-user-gesture-required \
--check-for-update-interval=31536000 \
--window-position=0,0"

# Flag tambahan dari /etc/ahass-client/chromium-flags.conf (diisi installer).
EXTRA_FLAGS=""
if [ -r /etc/ahass-client/chromium-flags.conf ]; then
  EXTRA_FLAGS="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' /etc/ahass-client/chromium-flags.conf | tr '\n' ' ')"
fi

# Sebagai root, sandbox Chromium harus dimatikan.
ROOT_FLAG=""
if [ "$(id -u)" = "0" ]; then
  ROOT_FLAG="--no-sandbox"
fi

echo "Membuka $URL (DISPLAY=$DISPLAY)" >&2
# shellcheck disable=SC2086
exec "$CHROME" $BASE_FLAGS $EXTRA_FLAGS $ROOT_FLAG --user-data-dir="$PROFILE_DIR" "$URL"
