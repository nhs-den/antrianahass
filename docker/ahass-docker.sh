#!/usr/bin/env bash
# ==========================================================================
# AHASS Panel — satu perintah untuk Docker (pasang / perbarui / lihat status).
#
# Contoh:
#   bash docker/ahass-docker.sh up          # bangun + jalankan panel (+ data volume)
#   bash docker/ahass-docker.sh up --kiosk  # sekaligus jalankan layar kiosk
#   bash docker/ahass-docker.sh logs        # ikuti log panel
#   bash docker/ahass-docker.sh password    # tampilkan password admin
#   bash docker/ahass-docker.sh update      # ambil kode terbaru + bangun ulang
#   bash docker/ahass-docker.sh status      # status container + versi panel
#   bash docker/ahass-docker.sh down        # hentikan (data TETAP tersimpan)
#
# Semua perintah memakai docker compose; data ada di volume `ahass-data`
# sehingga pengaturan, logo, dan video tidak hilang saat update.
# ==========================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
COMPOSE_FILE="$HERE/docker-compose.yml"
ENV_FILE="$HERE/.env"

log() { printf '\033[1;36m[ahass]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ahass]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '3,16p' "${BASH_SOURCE[0]}" | sed '/^# ====/d' | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
  -h|--help|help) usage; exit 0 ;;
esac

# --- docker & compose tersedia? -----------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  cat >&2 <<'MSG'
Docker belum terpasang. Pilih salah satu:
  Debian/Ubuntu/DietPi : curl -fsSL https://get.docker.com | sudo sh
  Raspberry Pi OS      : sudo apt-get install -y docker.io docker-compose-plugin
  Windows 10           : pasang Docker Desktop, lalu jalankan dari PowerShell/WSL
MSG
  exit 1
fi

has_compose_plugin() { docker compose version >/dev/null 2>&1; }
if has_compose_plugin; then
  COMPOSE=(docker compose -f "$COMPOSE_FILE")
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose -f "$COMPOSE_FILE")
else
  die "docker compose tidak tersedia (pasang paket docker-compose-plugin)."
fi

compose() {
  if [ -f "$ENV_FILE" ]; then
    "${COMPOSE[@]}" --env-file "$ENV_FILE" "$@"
  else
    "${COMPOSE[@]}" "$@"
  fi
}

ensure_env() {
  if [ ! -f "$ENV_FILE" ]; then
    cp "$HERE/.env.example" "$ENV_FILE"
    log "docker/.env dibuat dari contoh — isi AHASS_ADMIN_PASSWORD bila perlu."
  fi
}

CMD="${1:-up}"
shift || true

KIOSK=0
for arg in "$@"; do
  case "$arg" in
    --kiosk) KIOSK=1 ;;
    -h|--help) usage; exit 0 ;;
  esac
done

case "$CMD" in
  up|start)
    ensure_env
    log "Membangun image panel (sekali saja, berikutnya memakai cache)…"
    compose build panel
    if [ "$KIOSK" = "1" ]; then
      log "Menjalankan panel + kiosk…"
      compose --profile kiosk up -d
    else
      log "Menjalankan panel…"
      compose up -d panel
    fi
    sleep 3
    "${BASH_SOURCE[0]}" status
    ;;

  update)
    ensure_env
    if [ -d "$ROOT/.git" ] && git -C "$ROOT" rev-parse >/dev/null 2>&1; then
      log "Mengambil kode terbaru…"
      git -C "$ROOT" pull --ff-only || log "git pull dilewati (perubahan lokal / bukan repo)."
    fi
    compose build panel
    compose up -d --remove-orphans
    log "Selesai. Data di volume ahass-data tidak tersentuh."
    "${BASH_SOURCE[0]}" status
    ;;

  down|stop)
    compose down --remove-orphans
    log "Container berhenti. Data & pengaturan tetap di volume ahass-data."
    ;;

  restart)
    compose restart
    ;;

  logs)
    compose logs -f --tail=100 panel
    ;;

  status)
    compose ps || true
    IP=""
    if command -v curl >/dev/null 2>&1; then
      for url in http://127.0.0.1:8080/__ahass/api/health http://localhost:8080/__ahass/api/health; do
        body="$(curl -fsS --max-time 3 "$url" 2>/dev/null || true)"
        if [ -n "$body" ]; then
          echo "$body" | tr ',' '\n' | sed 's/[{}"]//g' | grep -E '^(version|port|dataDir|runtime)' | sed 's/^/  /'
          IP="$(echo "$body" | sed -n 's/.*"ips":\["\([^"]*\)".*/\1/p')"
          break
        fi
      done
    fi
    echo
    if [ -n "$IP" ]; then
      log "Panel:  http://$IP:8080/   admin: http://$IP:8080/admin"
    else
      log "Panel belum menjawab di port 8080 — cek: bash docker/ahass-docker.sh logs"
    fi
    ;;

  password)
    docker exec ahass-panel sh -c 'cat /var/lib/antrianahass/ADMIN-PASSWORD.txt 2>/dev/null || echo "(tidak ada berkas password; password diatur lewat AHASS_ADMIN_PASSWORD)"'
    ;;

  reset-password)
    NEWPASS="${1:-}"
    if [ -z "$NEWPASS" ]; then
      NEWPASS="$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    fi
    docker exec ahass-panel node /app/scripts/reset-password.js "$NEWPASS" \
      || die "Gagal mengganti password. Cek: docker logs ahass-panel"
    log "Password admin baru: $NEWPASS"
    log "Sesi admin lama otomatis berakhir setelah panel dijalankan ulang:"
    log "  bash docker/ahass-docker.sh restart"
    ;;

  shell)
    docker exec -it ahass-panel sh
    ;;

  doctor)
    docker exec ahass-panel node /app/scripts/doctor.js
    ;;

  *)
    usage
    exit 1
    ;;
esac
