#!/bin/sh
# ==========================================================================
# Menjalankan Chromium fullscreen di dalam container, menampilkan panel AHASS.
#
# Pembeda utama dengan deploy/start-kiosk.sh (native):
#   - X server ada di HOST (bukan Xvfb di dalam container), supaya layar
#     benar-benar tampil di TV. Container hanya butuh:
#         --network host
#         -e DISPLAY=:0
#         -v /tmp/.X11-unix:/tmp/.X11-unix
#         -v /dev/dri:/dev/dri            (opsional, untuk akselerasi GPU)
#   - Kalau X server host tidak tersedia (mis. di server tanpa layar), jatuh ke
#     mode "headless display" (Xvfb di dalam container) — berguna untuk uji.
# ==========================================================================
set -e

export DISPLAY="${DISPLAY:-:0}"
export HOME="${HOME:-/home/${KIOSK_USER:-ahass}}"
URL="${AHASS_URL:-http://127.0.0.1:8080/}"
PROFILE_DIR="${AHASS_PROFILE_DIR:-/tmp/chromium-profile}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-ahass}"

mkdir -p "$PROFILE_DIR" "$XDG_RUNTIME_DIR" 2>/dev/null || true
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

# --- ukuran layar (untuk Xvfb & window-size) ----------------------------
SCREEN_W="${SCREEN_W:-1920x1080x24}"
WIN_W="${SCREEN_W%%x*}"
REST="${SCREEN_W#*x}"
WIN_H="${REST%%x*}"

# --- tunggu X server host siap (maks ~20 detik) --------------------------
X_SCREEN="${DISPLAY#*:}"
X_SCREEN="${X_SCREEN%%.*}"
SOCKET="/tmp/.X11-unix/X${X_SCREEN}"
i=0
while [ ! -S "$SOCKET" ] && [ "$i" -lt 40 ]; do
  sleep 0.5
  i=$((i + 1))
done

if [ ! -S "$SOCKET" ]; then
  if [ "${AHASS_XVFB:-0}" = "1" ]; then
    echo "[kiosk] X host tidak ada -> menjalankan Xvfb internal ($SCREEN_W)" >&2
    Xvfb "$DISPLAY" -screen 0 "$SCREEN_W" -nolisten tcp &
    i=0
    while [ ! -S "$SOCKET" ] && [ "$i" -lt 40 ]; do
      sleep 0.25
      i=$((i + 1))
    done
  else
    echo "[kiosk] X server $DISPLAY tidak ditemukan (socket $SOCKET)." >&2
    echo "[kiosk] Jalankan container dengan: -e DISPLAY=:0 -v /tmp/.X11-unix:/tmp/.X11-unix --network host" >&2
    echo "[kiosk] Atau pakai AHASS_XVFB=1 untuk layar virtual di dalam container." >&2
    exit 1
  fi
fi

# --- matikan screen blanking & kursor ------------------------------------
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
  echo "[kiosk] Chromium tidak ditemukan di image." >&2
  exit 1
fi

# --- flag tambahan dari berkas (satu flag per baris, # = komentar) -------
FLAGS=""
if [ -f /etc/ahass/chromium-flags.conf ]; then
  while IFS= read -r line; do
    case "$line" in
      ''|\#*) continue ;;
    esac
    FLAGS="$FLAGS $line"
  done < /etc/ahass/chromium-flags.conf
fi
FLAGS="$FLAGS ${CHROMIUM_FLAGS:-}"

echo "[kiosk] $URL -> $CHROME (DISPLAY=$DISPLAY)" >&2

# Chromium di container berjalan sebagai non-root; --no-sandbox tetap dipakai
# karena sebagian host melarang namespace sandbox (mis. Docker di DietPi).
# shellcheck disable=SC2086
exec "$CHROME" \
  --no-sandbox \
  --kiosk \
  --start-fullscreen \
  --app="$URL" \
  --user-data-dir="$PROFILE_DIR" \
  --window-position=0,0 \
  --window-size="${WIN_W},${WIN_H}" \
  --no-first-run \
  --no-default-browser-check \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-translate \
  --disable-features=Translate \
  --overscroll-history-navigation=0 \
  --password-store=basic \
  --use-mock-keychain \
  --autoplay-policy=no-user-gesture-required \
  --disable-dev-shm-usage \
  $FLAGS
