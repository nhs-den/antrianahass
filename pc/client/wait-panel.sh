#!/bin/sh
# ExecStartPre untuk ahass-pc-kiosk.service.
#
# Menunggu panel di PC menjawab sebelum Chromium dibuka, supaya tidak muncul
# halaman putih "This site can't be reached" saat STB baru dinyalakan.
#
# Selalu keluar dengan kode 0: kalau PC belum siap, layar tetap dicoba
# (Chromium punya mekanisme reload sendiri) daripada unit gagal start.
#
# Lingkungan:
#   AHASS_PANEL_URL   alamat panel (default dibaca dari /etc/ahass-client/panel-url)
#   AHASS_WAIT_SECONDS  batas tunggu (default 120)

URL="${AHASS_PANEL_URL:-}"
if [ -z "$URL" ] && [ -r /etc/ahass-client/panel-url ]; then
  URL="$(head -1 /etc/ahass-client/panel-url)"
fi
[ -n "$URL" ] || exit 0

BASE="${URL%/}"
HEALTH="${BASE}/__ahass/api/health"
LIMIT="${AHASS_WAIT_SECONDS:-120}"

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fs -m 3 -o /dev/null "$HEALTH" 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 3 -O /dev/null "$HEALTH" 2>/dev/null
  else
    return 1
  fi
}

i=0
while [ "$i" -lt "$LIMIT" ]; do
  if fetch; then
    echo "panel siap setelah ${i}s ($HEALTH)"
    exit 0
  fi
  sleep 1
  i=$((i + 1))
done

echo "panel belum siap setelah ${LIMIT}s; tetap membuka layar"
exit 0
