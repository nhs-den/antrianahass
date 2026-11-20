#!/usr/bin/env bash
#
# Uji cepat kondisi panel + layar di STB. Tidak mengubah apa pun.
#
#   sudo bash stb/smoke-test.sh
#   sudo bash stb/smoke-test.sh --port=8080
#
set -uo pipefail

PORT="${PORT:-8080}"
for arg in "$@"; do
  case "$arg" in
    --port=*) PORT="${arg#*=}" ;;
    -h|--help) awk 'NR>1 && NR<=10 && /^#/ {sub(/^# ?/, ""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Argumen tidak dikenal: $arg" >&2; exit 1 ;;
  esac
done

c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_reset=$'\033[0m'
pass=0; fail=0

line() {
  local label="$1" state="$2" detail="${3:-}"
  case "$state" in
    ok)   printf '%s[ ok ]%s %-28s %s\n' "$c_ok" "$c_reset" "$label" "$detail"; pass=$((pass + 1)) ;;
    warn) printf '%s[warn]%s %-28s %s\n' "$c_warn" "$c_reset" "$label" "$detail"; pass=$((pass + 1)) ;;
    *)    printf '%s[fail]%s %-28s %s\n' "$c_err" "$c_reset" "$label" "$detail"; fail=$((fail + 1)) ;;
  esac
}

echo "Panel AHASS - uji kondisi STB"
echo "─────────────────────────────────────────────────────────────"

if systemctl is-active --quiet ahass-panel.service; then
  line "panel (ahass-panel)" ok "running"
else
  line "panel (ahass-panel)" fail "tidak running: journalctl -u ahass-panel -n 40"
fi

HEALTH="$(curl -fs -m 3 "http://127.0.0.1:${PORT}/__ahass/api/health" 2>/dev/null || true)"
if [ -n "$HEALTH" ]; then
  line "HTTP health" ok "$(printf '%s' "$HEALTH" | cut -c1-110)"
else
  line "HTTP health" fail "http://127.0.0.1:${PORT}/__ahass/api/health tidak menjawab"
fi

if systemctl is-active --quiet ahass-kiosk.service; then
  line "layar (ahass-kiosk)" ok "$(systemctl show -p SubState --value ahass-kiosk.service)"
else
  line "layar (ahass-kiosk)" fail "tidak running: journalctl -u ahass-kiosk -n 40"
fi

if [ -S /tmp/.X11-unix/X0 ]; then
  line "X server (:0)" ok "socket ada"
else
  line "X server (:0)" fail "socket /tmp/.X11-unix/X0 tidak ada"
fi

if pgrep -f "127.0.0.1:${PORT}" >/dev/null 2>&1; then
  line "Chromium" ok "$(pgrep -f "127.0.0.1:${PORT}" | head -1) pid"
else
  line "Chromium" fail "proses Chromium dengan URL panel tidak ditemukan"
fi

if command -v xwd >/dev/null 2>&1; then
  USER_X="$(systemctl show -p User --value ahass-kiosk.service 2>/dev/null | head -1)"
  XA=""
  for f in "$(getent passwd "${USER_X:-root}" 2>/dev/null | cut -d: -f6)/.Xauthority" /root/.Xauthority; do
    [ -s "$f" ] && XA="$f" && break
  done
  OUT=""
  if [ -n "$XA" ]; then
    OUT="$(XAUTHORITY="$XA" DISPLAY=:0 timeout 20 xwd -root -silent 2>/dev/null \
      | head -c 2000000 | od -An -tx1 -v 2>/dev/null || true)"
  else
    OUT="$(DISPLAY=:0 timeout 20 xwd -root -silent 2>/dev/null \
      | head -c 2000000 | od -An -tx1 -v 2>/dev/null || true)"
  fi
  if [ -n "$OUT" ]; then
    NONZERO="$(printf '%s' "$OUT" | awk '{for (i=1;i<=NF;i++) if ($i != "00") n++} END {print n+0}')"
    if [ "${NONZERO:-0}" -gt 3000 ]; then
      line "isi layar" ok "piksel bukan-hitam: $NONZERO"
    else
      line "isi layar" fail "layar tampak gelap (piksel bukan-hitam: ${NONZERO:-0}) - jalankan stb/screen-fix.sh"
    fi
  else
    line "isi layar" warn "tidak bisa diambil (xwd/Xauthority)"
  fi
else
  line "isi layar" warn "xwd tidak terpasang (apt install x11-apps)"
fi

MEM="$(free -m | awk '/^Mem:/ {printf "%s MB bebas dari %s MB", $7, $2}')"
line "memori" ok "$MEM"

if [ -e /dev/dri/card0 ]; then
  line "GPU (/dev/dri/card0)" ok "ada"
else
  line "GPU (/dev/dri/card0)" warn "tidak ada - rendering software (--disable-gpu)"
fi

echo "─────────────────────────────────────────────────────────────"
if [ "$fail" -eq 0 ]; then
  printf '%sSemua pemeriksaan penting lulus.%s\n' "$c_ok" "$c_reset"
  exit 0
fi
printf '%s%d pemeriksaan gagal.%s\n' "$c_err" "$fail" "$c_reset"
exit 1
