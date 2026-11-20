#!/bin/sh
# Menunggu panel Node menjawab sebelum Chromium dibuka.
# Dipakai sebagai ExecStartPre= di ahass-kiosk.service.
# Selalu keluar 0: kalau panel lambat, layar tetap dicoba (lebih baik daripada
# unit gagal start dan layar tetap hitam).
set -u

URL="${AHASS_URL:-http://127.0.0.1:8080/}"
HEALTH="${URL%/}/__ahass/api/health"
MAX="${AHASS_WAIT_SECONDS:-120}"

panel_ready() {
  if command -v curl >/dev/null 2>&1; then
    curl -fs -m 2 -o /dev/null "$HEALTH"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 2 -O /dev/null "$HEALTH"
  else
    sleep 1
    return 0
  fi
}

waited=0
while [ "$waited" -lt "$MAX" ]; do
  if panel_ready; then
    echo "panel siap setelah ${waited}s"
    exit 0
  fi
  waited=$((waited + 2))
  sleep 2
done

echo "panel belum siap setelah ${MAX}s; tetap membuka layar" >&2
exit 0
