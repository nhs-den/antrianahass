#!/usr/bin/env bash
#
# Memindahkan instalasi lama (mis. ~/ahass yang dijalankan manual) ke
# instalasi baru (~/antrianahass) TANPA kehilangan konfigurasi.
#
#   sudo bash deploy/migrate.sh --from /home/den/ahass
#   sudo bash deploy/migrate.sh --from /home/den/ahass --dry-run
#   sudo bash deploy/migrate.sh --from /home/den/ahass --no-install
#
# Yang dilakukan:
#   1. mencari config.json / logo / secret.key pada instalasi lama
#   2. menyalinnya ke DATA_DIR (/var/lib/antrianahass) + cadangan
#   3. menghentikan proses panel lama yang masih memakai port 8080
#   4. memasang versi baru (install.sh --no-deps)
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${APP_DIR:-/opt/antrianahass}"
DATA_DIR="${DATA_DIR:-/var/lib/antrianahass}"
PORT="${PORT:-8080}"
FROM_DIR=""
DRY_RUN=0
DO_INSTALL=1
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM_DIR="${2:-}"; shift 2 ;;
    --from=*) FROM_DIR="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-install) DO_INSTALL=0; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help)
      sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Argumen tidak dikenal: $1" >&2; exit 1 ;;
  esac
done

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_info=$'\033[36m'
log()  { echo "${c_info}[ahass]${c_reset} $*"; }
ok()   { echo "${c_ok}[ ok ]${c_reset} $*"; }
warn() { echo "${c_warn}[warn]${c_reset} $*"; }
die()  { echo "${c_err}[fail]${c_reset} $*" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = "1" ]; then echo "    (dry-run) $*"; else "$@"; fi; }

[ "$(id -u)" = "0" ] || die "Jalankan sebagai root: sudo bash deploy/migrate.sh --from /home/<user>/ahass"

echo
log "Sumber baru : $SRC_DIR (versi $(node -p "require('$SRC_DIR/package.json').version" 2>/dev/null || echo '?'))"
log "Data tujuan : $DATA_DIR"
[ -n "$FROM_DIR" ] && log "Instalasi lama: $FROM_DIR"
echo

# ------------------------------------------------------------------ 1. cari
CANDIDATES=()
[ -n "$FROM_DIR" ] && CANDIDATES+=("$FROM_DIR")
for guess in "$HOME/ahass" /home/*/ahass /opt/antrianahass "$SRC_DIR"; do
  [ -d "$guess" ] && CANDIDATES+=("$guess")
done

OLD_DATA=""
for dir in "${CANDIDATES[@]}"; do
  [ -d "$dir" ] || continue
  for sub in "$dir/data" "$dir"; do
    if [ -f "$sub/config.json" ] && [ "$(cd "$sub" && pwd)" != "$(cd "$DATA_DIR" 2>/dev/null && pwd || echo '/nonexistent')" ]; then
      OLD_DATA="$sub"
      break 2
    fi
  done
done

TARGET_HAS_CONFIG=0
[ -f "$DATA_DIR/config.json" ] && TARGET_HAS_CONFIG=1

if [ -z "$OLD_DATA" ]; then
  warn "Tidak ditemukan config.json lama. Tidak ada yang perlu dimigrasikan."
  if [ "$TARGET_HAS_CONFIG" = "1" ]; then
    ok "Instalasi baru sudah punya konfigurasi di $DATA_DIR."
  else
    warn "Konfigurasi akan dibuat baru (password admin baru) saat layanan dijalankan."
  fi
else
  ok "Konfigurasi lama ditemukan: $OLD_DATA"
  ls -1 "$OLD_DATA" 2>/dev/null | sed 's/^/    - /'

  if [ "$TARGET_HAS_CONFIG" = "1" ] && [ "$FORCE" != "1" ]; then
    warn "Data tujuan SUDAH punya config.json — migrasi dilewati agar tidak menimpa."
    warn "Gunakan --force bila memang ingin menimpa dengan data lama."
  else
    run mkdir -p "$DATA_DIR" "$DATA_DIR/uploads"
    if [ "$TARGET_HAS_CONFIG" = "1" ]; then
      BACKUP="$DATA_DIR/backup-$(date +%Y%m%d-%H%M%S)"
      log "Mencadangkan data tujuan ke $BACKUP…"
      run mkdir -p "$BACKUP"
      run cp -a "$DATA_DIR/config.json" "$BACKUP/" || true
      [ -f "$DATA_DIR/secret.key" ] && run cp -a "$DATA_DIR/secret.key" "$BACKUP/" || true
    fi

    for item in config.json secret.key ADMIN-PASSWORD.txt; do
      if [ -f "$OLD_DATA/$item" ]; then
        log "Menyalin $item…"
        run cp -a "$OLD_DATA/$item" "$DATA_DIR/$item"
      fi
    done
    if [ -d "$OLD_DATA/uploads" ] && [ -n "$(ls -A "$OLD_DATA/uploads" 2>/dev/null || true)" ]; then
      log "Menyalin logo / unggahan…"
      run cp -a "$OLD_DATA/uploads/." "$DATA_DIR/uploads/"
    fi
    ok "Konfigurasi lama dipindahkan."
  fi
fi

# ------------------------------------------------------- 2. proses lama
echo
OLD_PIDS="$(ss -ltnp 2>/dev/null | awk -v p=":$PORT" '$4 ~ p {print $0}' | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u || true)"
if [ -n "$OLD_PIDS" ]; then
  warn "Port $PORT sedang dipakai proses berikut:"
  for pid in $OLD_PIDS; do
    echo "    PID $pid → $(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | cut -c1-120)"
  done
  if systemctl is-active --quiet ahass-panel.service 2>/dev/null; then
    log "Proses tersebut adalah layanan ahass-panel (bukan versi manual) — dibiarkan, akan di-restart oleh pemasang."
  else
    warn "Sepertinya panel lama dijalankan manual. Proses ini harus dihentikan agar panel baru bisa memakai port $PORT."
    if [ "$DRY_RUN" = "1" ]; then
      echo "    (dry-run) kill $OLD_PIDS"
    elif [ "$FORCE" = "1" ]; then
      kill $OLD_PIDS 2>/dev/null || true
      sleep 1
      ok "Proses lama dihentikan."
    else
      printf "Hentikan sekarang? [y/N] "
      read -r answer
      if [ "${answer:-n}" = "y" ] || [ "${answer:-n}" = "Y" ]; then
        kill $OLD_PIDS 2>/dev/null || true
        sleep 1
        ok "Proses lama dihentikan."
      else
        warn "Dilewati. Panel baru kemungkinan gagal memakai port $PORT sampai proses itu dihentikan."
      fi
    fi
  fi
else
  ok "Port $PORT bebas."
fi

# ------------------------------------------------------------- 3. pasang
echo
if [ "$DO_INSTALL" = "1" ]; then
  log "Memasang versi baru dari $SRC_DIR…"
  if [ "$DRY_RUN" = "1" ]; then
    echo "    (dry-run) bash $SRC_DIR/deploy/install.sh --no-deps"
  else
    bash "$SRC_DIR/deploy/install.sh" --no-deps
  fi
else
  log "Lewati pemasangan (--no-install). Jalankan sendiri: sudo bash deploy/install.sh --no-deps"
fi

# ------------------------------------------------------------- 4. ringkas
echo
ok "Migrasi selesai."
cat <<'EOF'
  Langkah berikutnya:
   1. Buka admin → Ringkasan, pastikan versi baru & konfigurasi lama terbaca.
   2. Cek alamat DDMS + user/password di menu "Web DDMS" (password lama tetap ada).
   3. Bila ada aplikasi ulasan-google:  sudo bash deploy/install-ulasan.sh --dir ~/ulasan-google-main
   4. Setelah panel baru terbukti jalan, folder lama boleh dihapus/di-rename:
        mv ~/ahass ~/ahass-lama      # atau: rm -rf ~/ahass
   5. Bila Chromium / X server belum pernah dipasang di perangkat ini:
        sudo bash deploy/install.sh   # sekali saja, ikut memasang paket
EOF
echo
