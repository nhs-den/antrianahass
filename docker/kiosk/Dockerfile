# ==========================================================================
# AHASS Kiosk — Chromium fullscreen di Xvfb, satu container per layar.
#
# Dipakai bila perangkat tidak bisa memakai kiosk native (systemd + X):
#   - di server/PC yang sudah punya Docker (mode layar tunggal),
#   - di TV box/PC lain yang cukup `docker run` (tanpa install apa pun),
#   - di Pi/Compute Stick yang OS-nya sudah memakai Docker.
#
# Container ini TIDAK memakai Dockerfile panel; ia hanya browser yang membuka
# http://<host-panel>:8080/ sehingga selalu ikut versi terbaru panel.
#
# Build (di x86_64 / arm64 biasa):
#   docker build -f docker/kiosk/Dockerfile -t antrianahass-kiosk:latest docker/kiosk
# Build di Raspberry Pi 3 B+ (armv7, RAM 1 GB) — pakai image Debian armhf:
#   docker build --build-arg BASE=arm32v7/debian:bookworm-slim \
#     -f docker/kiosk/Dockerfile -t antrianahass-kiosk:pi docker/kiosk
# ==========================================================================
ARG BASE=debian:bookworm-slim
FROM ${BASE}

LABEL org.opencontainers.image.title="antrianahass-kiosk" \
      org.opencontainers.image.description="Chromium kiosk untuk panel AHASS" \
      org.opencontainers.image.source="https://github.com/nhs-den/antrianahass"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Jakarta \
    AHASS_URL=http://127.0.0.1:8080/ \
    SCREEN=0 \
    SCREEN_W=1920x1080x24 \
    KIOSK_USER=ahass

# Chromium + Xvfb + utilitas X minimal. Tanpa window manager (Chromium --kiosk
# berjalan sendiri di Xvfb; WM hanya menambah RAM). Di armhf paket Chromium
# tersedia di bookworm (chromium), di arm64 juga.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      chromium \
      xvfb \
      x11-xserver-utils \
      x11-utils \
      unclutter \
      fonts-dejavu-core \
      fonts-noto-color-emoji \
      tzdata \
      ca-certificates \
      curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -u 10001 -s /bin/bash "${KIOSK_USER}"

COPY start-kiosk.sh /usr/local/bin/ahass-kiosk
COPY chromium-flags.conf /etc/ahass/chromium-flags.conf
RUN chmod 755 /usr/local/bin/ahass-kiosk \
 && mkdir -p /home/${KIOSK_USER}/.config/chromium /tmp/.X11-unix \
 && chown -R ${KIOSK_USER}:${KIOSK_USER} /home/${KIOSK_USER}

USER ${KIOSK_USER}
WORKDIR /home/${KIOSK_USER}

# Tidak ada EXPOSE: layar tampil di X server host (DISPLAY) yang di-mount.
CMD ["/usr/local/bin/ahass-kiosk"]
