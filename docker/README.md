# Menjalankan AHASS Panel dengan Docker

Panduan ini membuat panel berjalan **sama seperti versi systemd**, tetapi tanpa
memasang Node/Chromium di sistem: cukup Docker. Cocok untuk PC Windows 10
(Docker Desktop/WSL), server kecil, Raspberry Pi, maupun Intel Compute Stick
yang OS-nya sudah memasang Docker.

Yang berjalan:

| Container | Isi | Port |
|---|---|---|
| `ahass-panel` | server panel (`server.js`), halaman `/`, admin `/admin`, proxy DDMS, widget ulasan bawaan | **8080** dan **3000** |
| `ahass-kiosk` | Chromium fullscreen (opsional, satu per layar) | – (menampil di TV) |

Data (pengaturan, password admin, logo, gambar, video) disimpan di **volume
`ahass-data`** → `docker compose down` tidak menghapus apa pun, dan update
cukup bangun ulang image.

---

## 1. Cara tercepat (satu perintah)

```bash
cd antrianahass
bash docker/ahass-docker.sh up
```

Skrip ini membuat `docker/.env` dari contoh, membangun image, menjalankan
container, lalu mencetak alamat panel + versinya.

Layar kiosk sekaligus (perangkat ini punya TV/monitor dan X server):

```bash
bash docker/ahass-docker.sh up --kiosk
```

Perintah lain:

```bash
bash docker/ahass-docker.sh status          # status + versi + alamat panel
bash docker/ahass-docker.sh logs            # ikuti log panel
bash docker/ahass-docker.sh password        # tampilkan password admin
bash docker/ahass-docker.sh reset-password "PasswordBaru123"
bash docker/ahass-docker.sh update          # ambil kode terbaru + bangun ulang
bash docker/ahass-docker.sh down            # berhenti (data tetap)
bash docker/ahass-docker.sh doctor          # pemeriksaan kesehatan
bash docker/ahass-docker.sh shell           # masuk ke container (debug)
```

---

## 2. Cara manual (docker compose)

```bash
cp docker/.env.example docker/.env      # isi AHASS_ADMIN_PASSWORD
docker compose -f docker/docker-compose.yml --env-file docker/.env up -d --build
```

Atau tanpa berkas `.env` (lewat Environment langsung):

```bash
docker run -d --name ahass-panel --restart unless-stopped \
  --network host \
  -e TZ=Asia/Jakarta \
  -e AHASS_ADMIN_PASSWORD=PasswordBaru123 \
  -e AHASS_DDMS_URL=https://web-h2-cbr.daya-dms.id \
  -v ahass-data:/var/lib/antrianahass \
  antrianahass:latest
```

Buka `http://IP-PERANGKAT:8080/` (panel) dan `http://IP-PERANGKAT:8080/admin`.

Tanpa `--network host` (mis. Docker Desktop di Windows), ganti dengan
`-p 8080:8080 -p 3000:3000` dan set `-e AHASS_DISPLAY_IP=IP-PC` supaya baris
alamat di layar menampilkan IP yang benar (bukan IP container `172.x`).

---

## 3. Variabel lingkungan

| Variabel | Arti | Bawaan |
|---|---|---|
| `AHASS_ADMIN_PASSWORD` | Password admin saat pertama dibuat | acak (lihat `ADMIN-PASSWORD.txt`) |
| `AHASS_DDMS_URL` | Alamat server DDMS awal | `https://web-h2-cbr.daya-dms.id` |
| `AHASS_DISPLAY_IP` | IP yang ditampilkan untuk STB/PC (boleh dipisah koma) | deteksi otomatis |
| `AHASS_DATA_DIR` | Folder data di dalam container | `/var/lib/antrianahass` |
| `TZ` | Zona waktu jam & jadwal | `Asia/Jakarta` |
| `PORT` / `HOST` | Port & alamat dengar panel | `8080` / `0.0.0.0` |
| `AHASS_RUNTIME` | Penanda lingkungan (`docker`) | otomatis |

Password admin di dalam container:

```bash
docker exec ahass-panel cat /var/lib/antrianahass/ADMIN-PASSWORD.txt
```

---

## 4. Kiosk (layar TV) di dalam Docker

Container kiosk hanya berisi Chromium + Xvfb. Ia membuka panel; panel tetap
dilayani container `panel`. Syaratnya:

1. **X server host** tersedia (biasanya `:0` pada desktop yang login otomatis).
2. Container dijalankan dengan:

```bash
docker compose -f docker/docker-compose.yml --profile kiosk up -d
```

Detail yang dipakai: `network_mode: host`, `DISPLAY=:0`,
`-v /tmp/.X11-unix:/tmp/.X11-unix` (socket X), `SCREEN_W=1920x1080x24`.

Uji tanpa TV (layar virtual di dalam container):

```bash
docker run --rm --network host -e AHASS_XVFB=1 -e AHASS_URL=http://127.0.0.1:8080/ \
  antrianahass-kiosk:latest
```

### Raspberry Pi 3 B+ (armv7)

Image kiosk bawaan memakai `debian:bookworm-slim` (arm64 / x86_64). Untuk Pi 3
B+ (32-bit) bangun dengan base armhf:

```bash
docker build --build-arg BASE=arm32v7/debian:bookworm-slim \
  -f docker/kiosk/Dockerfile -t antrianahass-kiosk:pi docker/kiosk
AHASS_KIOSK_IMAGE=antrianahass-kiosk:pi \
  docker compose -f docker/docker-compose.yml --profile kiosk up -d
```

Di Pi 3 B+ (RAM 1 GB) jalankan **hanya satu** container kiosk, dan biarkan
flag di `docker/kiosk/chromium-flags.conf` apa adanya (1 renderer, heap 128 MB).

---

## 5. Auto-start saat perangkat menyala

Container sudah `restart: unless-stopped`, jadi Docker sendiri yang
menjalankannya setelah boot. Bila perangkat juga harus menyalakan layar kiosk,
pakai unit systemd contoh:

```bash
sudo cp docker/ahass-compose.service /etc/systemd/system/
sudo systemctl enable --now ahass-compose
```

---

## 6. Memperbarui versi

```bash
bash docker/ahass-docker.sh update
```

Isinya: `git pull` → `docker compose build panel` → `up -d --remove-orphans`.
Volume data tidak disentuh. Versi yang berjalan bisa dilihat:

```bash
curl -s http://127.0.0.1:8080/__ahass/api/health
```

Lalu buka `/admin` dan tekan **Ctrl+Shift+R** — pastikan tertulis
**“Versi halaman ini: 1.5.0”** (atau lebih baru).

---

## 7. Bila ada masalah

| Gejala | Penyebab & solusi |
|---|---|
| Panel tidak terbuka | `docker ps` (container jalan?), `docker logs ahass-panel`, lalu `curl -s localhost:8080/__ahass/api/health` |
| Alamat di layar `172.17.x.x` | Pakai `--network host`, atau set `AHASS_DISPLAY_IP=IP-PC` |
| Layar DDMS hitam | Cek `docker exec ahass-panel curl -sk -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/ddms` → `302` normal. Bila `502`, container tidak bisa keluar ke DDMS (proxy/firewall) |
| Kiosk: `X server :0 tidak ditemukan` | X host belum jalan, atau socket tidak di-mount; jalankan dengan user yang sama dengan sesi desktop |
| Kiosk hitam di Pi/Compute Stick | Tambahkan `--memory=512m`, pastikan hanya 1 container kiosk, cek `docker logs ahass-kiosk` |
| Password admin lupa | `bash docker/ahass-docker.sh reset-password "Baru123"` |
| Ingin mulai dari nol | `docker compose -f docker/docker-compose.yml down -v` (**menghapus semua pengaturan**) |

Data ada di volume `ahass-data`. Backup:

```bash
docker run --rm -v ahass-data:/data -v "$PWD":/out alpine \
  tar czf /out/ahass-data-backup.tgz -C /data .
```

---

## 8. Catatan untuk Windows 10 (PC)

Docker Desktop memakai WSL2 dan **tidak mendukung `network_mode: host`**.
Untuk PC:

```bash
docker run -d --name ahass-panel --restart unless-stopped ^
  -p 8080:8080 -p 3000:3000 ^
  -e AHASS_DISPLAY_IP=192.168.1.10 ^
  -v ahass-data:/var/lib/antrianahass ^
  antrianahass:latest
```

Akses dari STB: `http://192.168.1.10:8080/`. Untuk kiosk di PC yang sama,
cara paling andal tetap versi native (`pc/install.sh`) — Chromium di dalam
Docker Desktop tidak bisa menampilkan jendela ke desktop Windows.
