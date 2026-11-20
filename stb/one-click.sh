#!/usr/bin/env bash
#
# Satu perintah untuk STB Armbian/ophub (Amlogic S905X dan sejenisnya).
#
#   curl -fsSL https://raw.githubusercontent.com/nhs-den/antrianahass/main/stb/one-click.sh | sudo bash
#
# Skrip ini: memasang git/curl bila perlu, mengambil repo (klon atau perbarui),
# lalu menjalankan stb/install.sh yang memasang panel + memperbaiki layar
# sampai benar-benar tampil.
#
# Argumen tambahan diteruskan ke install.sh, contoh:
#   curl -fsSL .../one-click.sh | sudo bash -s -- --resolution=1920x1080
#
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/nhs-den/antrianahass.git}"
SRC_DIR="${SRC_DIR:-/opt/antrianahass-src}"
BRANCH="${BRANCH:-main}"

c_ok=$'\033[32m'; c_err=$'\033[31m'; c_info=$'\033[36m'; c_reset=$'\033[0m'
log() { echo "${c_info}[ahass]${c_reset} $*"; }
ok()  { echo "${c_ok}[ ok ]${c_reset} $*"; }
die() { echo "${c_err}[fail]${c_reset} $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "Jalankan sebagai root: curl -fsSL ... | sudo bash"

log "Menyiapkan prasyarat (git, curl)…"
if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  apt-get update -qq || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends git curl ca-certificates >/dev/null
fi

if [ -d "$SRC_DIR/.git" ]; then
  log "Memperbarui sumber di $SRC_DIR (branch $BRANCH)…"
  git -C "$SRC_DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$SRC_DIR" reset --hard FETCH_HEAD
else
  log "Mengambil sumber ke $SRC_DIR…"
  rm -rf "$SRC_DIR"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$SRC_DIR"
fi
ok "Sumber siap: $(git -C "$SRC_DIR" log --oneline -1)"

exec bash "$SRC_DIR/stb/install.sh" "$@"
