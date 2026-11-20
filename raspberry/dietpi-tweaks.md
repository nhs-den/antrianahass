# Tweak DietPi untuk Raspberry Pi 3 B+ (16 GB)

Semua langkah di bawah dilakukan **sekali** setelah `raspberry/install.sh`.
Installer sudah menangani sysctl, journald, dan logrotate; dokumen ini
menjelaskan sisanya yang harus lewat perkakas DietPi.

## 1. Autostart

```bash
sudo dietpi-autostart
```

| Mode panel | Pilihan yang benar | Kenapa |
|---|---|---|
| `desktop` | **Automatic login** → desktop (biasanya nomor 2) | LXDE harus jalan agar `~/.config/lxsession/LXDE/autostart` dieksekusi |
| `kiosk` | **Manual login** (biasanya nomor 0) | Desktop tidak boleh jalan; `ahass-kiosk.service` mengambil alih tty1 |

Jangan mencampur: desktop + unit `ahass-kiosk` aktif = dua Chromium berebut
layar dan profil.

Cek nilai saat ini:

```bash
cat /boot/dietpi/.dietpi-autostart_index 2>/dev/null \
  || cat /boot/firmware/dietpi/.dietpi-autostart_index 2>/dev/null
```

## 2. zram (wajib untuk 1 GB RAM)

```bash
sudo dietpi-config
# 4  Performance Options  →  Zram  →  aktifkan, ukuran ~256 MB
```

Verifikasi:

```bash
zramctl
free -m
swapon --show
```

Dengan zram aktif, `vm.swappiness=100` (dipasang installer) membuat kernel
memindahkan halaman dingin ke zram lebih awal — ini yang mencegah OOM killer
mematikan Chromium saat layar berjalan lama.

Kalau Anda **tidak** memakai zram dan tetap ingin swapfile di microSD:

```bash
sudo sysctl vm.swappiness=10
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.d/99-ahass-pi.conf
```

## 3. GPU memory split

Chromium butuh memori GPU untuk compositing:

```bash
sudo dietpi-config
# 4  Performance Options  →  GPU/RAM  →  128 MB
```

Untuk mode `kiosk` (tanpa desktop) 64–128 MB cukup. Jangan 256 MB — RAM 1 GB
akan terpotong percuma.

## 4. Nonaktifkan layanan yang tidak dipakai

Setiap layanan latar memakan RAM yang dibutuhkan Chromium. Contoh yang sering
tidak perlu di panel:

```bash
sudo systemctl disable --now cloudshell 2>/dev/null    # dietpi-cloudshell
sudo systemctl disable --now bluetooth 2>/dev/null
sudo systemctl disable --now avahi-daemon 2>/dev/null  # hanya kalau tak perlu .local
sudo systemctl disable --now cron 2>/dev/null          # hanya kalau tak ada cron job
```

Cek dampaknya sebelum/sesudah:

```bash
systemd-analyze blame | head -10
systemctl --type=service --state=running --no-pager
```

## 5. Umur microSD

Installer sudah membatasi jurnal (64 MB), log launcher (2 MB), dan cache
Chromium (32 MB). Tambahan:

```bash
# bersihkan jurnal lama
sudo journalctl --vacuum-size=64M

# berhenti menulis atime
sudo sed -i 's/\bdefaults\b/defaults,noatime/' /etc/fstab   # hati-hati, cek dulu isinya
sudo mount -o remount /

# pakai tmpfs untuk /tmp dan /var/log kalau RAM cukup (opsional, tidak untuk 1 GB)
```

Untuk 1 GB RAM **jangan** memindahkan `/tmp` ke tmpfs — Chromium memakai
`/tmp` untuk profil sementara.

## 6. Suhu dan throttling

Pi 3 B+ akan menurunkan clock di 80–85 °C, dan Chromium langsung terasa
lambat. Cek:

```bash
vcgencmd measure_temp
vcgencmd get_throttled     # 0x0 = tidak ada throttling
```

Pasang heatsink, dan pastikan casing punya ventilasi. Jangan menaikkan
`over_voltage`.

## 7. Waktu dan zona waktu

Jam di kotak 1 bergantung pada waktu sistem:

```bash
sudo timedatectl set-timezone Asia/Jakarta
timedatectl
```

Kalau Pi tidak punya RTC (Pi 3 B+ tidak punya), `systemd-timesyncd` akan
menyesuaikan waktu setelah WiFi/Ethernet tersambung — beberapa detik pertama
setelah boot jam bisa masih waktu terakhir mati.

## 8. Setelah semua tweak

```bash
sudo reboot
```

Yang diharapkan setelah boot:

1. ±15–25 detik: desktop (mode `desktop`) atau layar panel langsung (mode `kiosk`).
2. Panel menjawab: `curl -s http://127.0.0.1:8080/__ahass/api/health`.
3. Chromium fullscreen dengan sisi kanan DDMS dan lima kotak di kiri.
4. `free -m` menunjukkan sisa RAM > 250 MB, `zramctl` aktif.
