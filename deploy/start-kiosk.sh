#!/bin/sh
# Menjalankan Chromium dalam mode kiosk fullscreen untuk panel AHASS.
# Dipanggil oleh systemd (ahass-kiosk.service) lewat xinit.

set -e

export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/ahass-kiosk}"
export HOME="${HOME:-/home/$(id -un)}"
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true

# Tunggu X server siap (maks 10 detik) supaya Chromium tidak gagal terhubung.
X_SCREEN="${DISPLAY#*:}"
X_SCREEN="${X_SCREEN%%.*}"
SOCKET="/tmp/.X11-unix/X${X_SCREEN}"
i=0
while [ ! -S "$SOCKET" ] && [ $i -lt 20 ]; do
  sleep 0.5
  i=$((i + 1))
done
if [ ! -S "$SOCKET" ]; then
  echo "X server tidak siap pada $DISPLAY (socket $SOCKET tidak ada)." >&2
  echo "Periksa: sudo bash /opt/antrianahass/deploy/fix-kiosk.sh" >&2
fi

URL="${AHASS_URL:-http://127.0.0.1:8080/}"
PROFILE_DIR="${AHASS_PROFILE_DIR:-/var/lib/antrianahass/chromium}"

mkdir -p "$PROFILE_DIR"

# matikan screen blanking / DPMS agar layar tidak tidur
if command -v xset >/dev/null 2>&1; then
  xset s off 2>/dev/null || true
  xset -dpms 2>/dev/null || true
  xset s noblank 2>/dev/null || true
fi
if command -v xsetroot >/dev/null 2>&1; then
  xsetroot -solid '#000000' 2>/dev/null || true
fi

# sembunyikan kursor saat tidak dipakai
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
  echo "Chromium tidak ditemukan. Pasang dengan: apt-get install -y chromium" >&2
  echo "Atau jalankan: sudo bash /opt/antrianahass/deploy/fix-kiosk.sh" >&2
  exit 1
fi

echo "Menjalankan $CHROME untuk $URL (DISPLAY=$DISPLAY)" >&2

DEFAULT_FLAGS="--kiosk --start-fullscreen --no-first-run --no-default-browser-check --noerrdialogs \
--disable-infobars --disable-session-crashed-bubble --disable-translate --disable-sync \
--disable-background-networking --disable-component-update --disable-default-apps \
--disable-extensions --disable-pinch --overscroll-history-navigation=0 \
--disable-features=Translate,MediaRouter,OptimizationHints,CalculateNativeWinOcclusion,InterestFeedContentSuggestions \
--password-store=basic --use-mock-keychain --autoplay-policy=no-user-gesture-required \
--check-for-update-interval=31536000 --renderer-process-limit=3 \
--js-flags=--max-old-space-size=256 --disk-cache-size=67108864 \
--window-position=0,0 --user-data-dir=$PROFILE_DIR"

# Kiosk berjalan tanpa akun desktop; bila dijalankan sebagai root, sandbox harus dimatikan.
if [ "$(id -u)" = "0" ]; then
  DEFAULT_FLAGS="$DEFAULT_FLAGS --no-sandbox"
fi

# shellcheck disable=SC2086
exec "$CHROME" $DEFAULT_FLAGS ${CHROMIUM_FLAGS:-} "$URL"
