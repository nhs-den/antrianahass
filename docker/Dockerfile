# ==========================================================================
# AHASS Panel — image Docker untuk server panel (kiosk web + admin)
#
# Isi image: Node.js + server.js + public/ + lib/ + scripts/.
# TIDAK berisi Chromium. Untuk layar gunakan docker/kiosk/Dockerfile
# (satu container kiosk per layar, cukup `--network host` + akses /dev/dri).
#
# Ukuran kecil dan jalan di CPU lemah (Pi 3 B+ / Compute Stick):
#   alpine + node, tanpa dependency npm (proyek ini tanpa node_modules).
#
# Build:  docker build -f docker/Dockerfile -t antrianahass:latest .
# ==========================================================================
FROM node:20-alpine

LABEL org.opencontainers.image.title="antrianahass" \
      org.opencontainers.image.description="Panel display AHASS (DDMS 70% + 5 kotak info 30%)" \
      org.opencontainers.image.source="https://github.com/nhs-den/antrianahass"

# tzdata: supaya jadwal & jam mengikuti zona waktu lokal (Asia/Jakarta).
# curl:    dipakai HEALTHCHECK di bawah.
RUN apk add --no-cache tzdata curl \
 && addgroup -g 10001 -S ahass \
 && adduser -u 10001 -S -G ahass -h /var/lib/antrianahass ahass

ENV NODE_ENV=production \
    TZ=Asia/Jakarta \
    PORT=8080 \
    HOST=0.0.0.0 \
    AHASS_DATA_DIR=/var/lib/antrianahass \
    AHASS_RUNTIME=docker

WORKDIR /app

# Hanya berkas yang dibutuhkan server (tanpa docs/installer/docker).
COPY --chown=root:root package.json server.js ./
COPY --chown=root:root lib ./lib
COPY --chown=root:root public ./public
COPY --chown=root:root scripts ./scripts

# Folder data: config.json, uploads/, secret.key, ADMIN-PASSWORD.txt.
# Di-mount sebagai volume oleh docker-compose / docker run.
RUN mkdir -p /var/lib/antrianahass/uploads \
 && chown -R ahass:ahass /var/lib/antrianahass

USER ahass

EXPOSE 8080 3000

# /ddms sengaja tidak dipakai: butuh jaringan keluar ke server DDMS.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/__ahass/api/health || exit 1

CMD ["node", "server.js"]
