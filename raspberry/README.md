# Panel AHASS di Raspberry Pi 3 B+

Pemasang khusus untuk **Raspberry Pi 3 Model B+** dengan **DietPi** dan kartu
microSD **16 GB**. Aplikasinya sama dengan versi Intel Compute Stick
(satu proses Node tanpa dependensi, tanpa build step), hanya beda cara
memasang dan setelan hemat memorinya.

| | Versi Compute Stick | Versi Raspberry Pi 3 B+ |
|---|---|---|
| Proses | 1 Node + Chromium | idem |
| RAM | 2 GB | **1 GB** → Chromium dibatasi 1 renderer, heap V8 128 MB |
| Penyimpanan | eMMC 32 GB | **microSD 16 GB** → jurnal 64 MB, log kiosk 2 MB |
| Layar | desktop LXDE + autostart | desktop (default bila LXDE ada) **atau** kiosk tty1 |
| Batas memori Node | 384 MB | **320 MB** |
| Flag Chromium | `--renderer-process-limit=3` | `--renderer-process-limit=1`, `--enable-low-end-device-mode` |

Tata letak tampilan tetap: **70% DDMS** (auto-login) di kanan, **30%** lima kotak
di kiri (jam/tanggal, logo, ulasan Google, gambar sosmed, video).

> **Salah folder?** Folder ini memasang panel **mandiri** di Pi (Pi = server +
> layar sekaligus). Kalau Anda ingin Pi hanya jadi **layar** yang menampilkan
> panel dari sebuah PC, pakai [`pc/README.md`](../pc/README.md) — jangan
> campur keduanya di satu perangkat.

---

## 1. Prasyarat

1. **DietPi** terpasang di microSD 16 GB, idealnya image **arm64**
   (DietPi untuk Pi 3 B+ menyediakan arm64; 32-bit tetap jalan tapi Chromium
   lebih boros memori).
2. Sudah bisa `ssh` ke Pi dan punya koneksi internet.
3. Repo ini sudah diklon di Pi:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/nhs-den/antrianahass.git ~/antrianahass
```

> Port Ethernet Pi 3 B+ lebih cepat dan lebih hemat daya daripada WiFi.
> Kalau kabel memungkinkan, pakai kabel — boot dan auto-login DDMS jadi lebih
> cepat karena tidak menunggu asosiasi WiFi.

---

## 2. Pemasangan (3 langkah)

### Langkah 1 — pasang aplikasi

```bash
sudo bash ~/antrianahass/raspberry/install.sh
```

Tanpa argumen, installer:

- mendeteksi board, arsitektur, RAM, dan ruang disk,
- memasang paket minimal (`nodejs`, `chromium`, X, `curl`, `unclutter`,
  `logrotate`),
- membuat pengguna sistem `ahass` dan direktori data `/var/lib/antrianahass`,
- menyalin aplikasi ke `/opt/antrianahass`,
- memasang unit `ahass-panel.service` + `ahass-restart.timer` (restart harian 03:00),
- **memilih mode layar otomatis**: kalau LXDE terdeteksi → `desktop`,
  kalau tidak → `kiosk`,
- menerapkan tweak microSD/RAM (sysctl, journald 64 MB, logrotate),
- menyalakan panel dan mengecek `/__ahass/api/health`.

Opsi yang sering dipakai:

```bash
sudo bash raspberry/install.sh --mode=desktop   # paksa desktop LXDE
sudo bash raspberry/install.sh --mode=kiosk     # paksa kiosk tty1
sudo bash raspberry/install.sh --no-deps        # lewati apt-get (perbarui kode saja)
sudo bash raspberry/install.sh --no-tweaks      # jangan sentuh sysctl/journald
sudo bash raspberry/install.sh --port=8081      # ganti port panel
sudo bash raspberry/install.sh --user=dietpi    # pengguna yang menjalankan layar
```

### Langkah 2 — tentukan mode layar

**Mode `desktop` (disarankan, paling terbukti)**

Layar memakai desktop LXDE lalu Chromium fullscreen di atasnya.

```bash
sudo dietpi-software            # 'Desktops' → LXDE  (kalau belum ada)
sudo dietpi-autostart           # pilih 'Automatic login' (desktop) — biasanya nomor 2
sudo reboot
```

Installer sudah menulis `@/usr/local/bin/ahass-kiosk-desktop.sh` ke
`~/.config/lxsession/LXDE/autostart`. Jangan menambahkan entri kedua lewat
`~/.config/autostart/` — installer menghapus entri duplikat karena dua
launcher akan berebut profil Chromium yang sama.

**Mode `kiosk` (paling ringan, tanpa desktop)**

Chromium dijalankan langsung di tty1 lewat `xinit`, hemat ±100 MB RAM.

```bash
sudo dietpi-autostart           # pilih 'Manual login' — biasanya nomor 0
sudo reboot
```

Pada mode ini `ahass-kiosk.service` yang mengurus layar, dan installer
menghapus baris autostart LXDE supaya tidak dobel.

### Langkah 3 — buka admin dan isi konfigurasi

Dari komputer lain di jaringan yang sama:

```
http://IP-PI:8080/admin
```

Password admin ada di `/var/lib/antrianahass/ADMIN-PASSWORD.txt`:

```bash
sudo cat /var/lib/antrianahass/ADMIN-PASSWORD.txt
```

Yang perlu diisi sekali:

1. **Web DDMS** — alamat DDMS, username, password.
   Setelah login berhasil, salin **path board antrean** dari address bar dan
   tempel ke kolom *Path halaman*. Tanpa ini, tampilan akan jatuh ke halaman
   "Selamat Datang" setiap kali halaman dimuat ulang.
2. **Logo** — unggah `logo-ahass-munjul-motor.png`.
3. **Ulasan Google** — tempel potongan `<script>…loader.js?kiosk=1</script>`
   apa adanya (mode *script*).
4. **Kotak 4 & 5** — daftar gambar/video sosmed.
5. **Layout** — rasio kotak kiri (default 1 / 1 / 1.9 / 1.15 / 1.55).

---

## 3. Verifikasi

```bash
# panel hidup dan sehat
curl -s http://127.0.0.1:8080/__ahass/api/health; echo
systemctl status ahass-panel --no-pager | head -5
systemctl list-timers ahass-restart.timer --no-pager

# mode desktop
tail -20 ~/ahass-kiosk-desktop.log
pgrep -af ahass-kiosk-desktop.sh | wc -l     # harus 1

# mode kiosk
sudo journalctl -u ahass-kiosk -n 20 --no-pager
pgrep -af chromium | head -3
```

Log launcher mode desktop mencatat tiga baris penting:

```
=== 2026-11-20 08:15:02 launcher dipanggil (pid 812, user dietpi) ===
2026-11-20 08:15:02 pakai chromium, profil /home/dietpi/.config/ahass-kiosk
2026-11-20 08:15:04 panel siap (tunggu 2s), buka Chromium
```

Selisih `dipanggil` → `panel siap` biasanya 1–3 detik. Kalau sampai puluhan
detik, panel-lah yang lambat — periksa `systemctl status ahass-panel`.

---

## 4. Struktur folder ini

```
raspberry/
├── install.sh                # pemasang utama (idempoten)
├── uninstall.sh              # pelepas (opsional --purge)
├── screen-fix.sh             # perbaikan layar bertahap + verifikasi piksel
├── kiosk-desktop.sh          # launcher mode desktop: tunggu panel + watchdog + log
├── chromium-flags.conf       # flag Chromium untuk RAM 1 GB
├── units/
│   ├── ahass-panel.service   # Node :8080, MemoryMax=320M
│   ├── ahass-kiosk.service   # mode kiosk (tty1 + xinit)
│   ├── ahass-restart.service # restart panel harian, kondisional
│   └── ahass-restart.timer   # 03:00
├── logrotate-ahass.conf      # batasi log launcher (2 MB, 2 rotasi)
├── journald-ahass-small.conf # jurnal maksimal 64 MB
├── sysctl-ahass-pi.conf      # swappiness zram, dirty page
├── dietpi-tweaks.md          # zram, GPU split, autostart, umur microSD
└── README.md                 # dokumen ini
```

---

## 5. Kalau layar hitam, terpotong, atau tidak fullscreen

Tiga masalah berbeda, dengan obat yang berbeda. Cek berurutan — jangan menebak.

### 5.1 Layar hitam + kursor berkedip

```bash
sudo bash /opt/antrianahass/raspberry/screen-fix.sh
```

Skrip itu mencoba tiga langkah dan **membuktikan** hasilnya dengan membaca isi
layar lewat `xwd` (layar hitam tidak dianggap berhasil):

| Langkah | Yang diubah | Untuk kasus |
|---|---|---|
| 0 | apa adanya | GPU/driver normal |
| 1 | `+ --disable-gpu` | driver Mali/VC4 bermasalah di Chromium |
| 2 | `xserver-xorg-legacy` + layar sebagai root | Xorg tidak boleh membuka TTY sebagai non-root |
| 3 | diagnosa lengkap | sisanya: kirim keluarannya |

Reset semua perubahan: `sudo bash /opt/antrianahass/raspberry/screen-fix.sh --reset`
Hanya melapor tanpa mengubah: `... --diagnose`

### 5.2 Panel tidak fullscreen / layout jadi bertumpuk

Gejala: panel kiri (jam/logo) pindah ke **bawah**, dan jendela Chromium lebih
kecil dari layar.

```bash
sudo -u dietpi DISPLAY=:0 xwininfo -root -tree | tr -d '\000' \
  | sed -n 's/.*"AHASS[^"]*".*  \([0-9]*x[0-9]*[+-][0-9]*[+-][0-9]*\).*/\1/p' | head -1
sudo -u dietpi DISPLAY=:0 xdpyinfo | grep dimensions
```

Kalau geometri jendela ≠ ukuran layar, penyebabnya **tidak ada window manager**:
Chromium mengabaikan `--kiosk` tanpa WM. Installer sekarang memasang
`matchbox-window-manager` dan menjalankan lewat `/usr/local/bin/ahass-kiosk-boot.sh`.
Untuk memperbaikinya pada pemasangan lama:

```bash
sudo apt-get install -y matchbox-window-manager
sudo bash /opt/antrianahass/raspberry/install.sh --no-deps
```

### 5.3 Tepi layar terpotong (overscan TV)

Gejala: jam terpotong di kiri, "Refresh In …" terpotong di kanan, atau ada
bingkai hitam di tepi.

Buka **admin → Tampilan → "Pas agar tidak terpotong (overscan TV)"**:

- turunkan **Skala panel** ke 94–96%,
- geser dengan tombol **◀ ▶ ▲ ▼** (1 klik = 4 px) sampai tepi terlihat,
- tekan **Simpan pas layar** — layar kiosk berubah seketika, tanpa restart.

Kalau masih ada bingkai hitam dari TV itu sendiri, nyalakan
**"Matikan overscan TV"** di bagian Resolusi (atau di TV: *Picture → Aspect →
16:9 / Just Scan*).

### 5.4 Resolusi salah (mis. TV 1080p tapi tampil 720p)

Admin → **Tampilan → Resolusi layar perangkat** → pilih mode → **Terapkan &
reboot**.

Yang dilakukan aplikasi:

1. menghapus `hdmi_group` / `hdmi_mode` lama di `/boot/firmware/config.txt`,
2. **menghapus `framebuffer_width` / `framebuffer_height`** — baris ini
   mengunci resolusi lebih kuat daripada `hdmi_mode`, jadi perubahan mode tidak
   akan terlihat selama baris tersebut ada,
3. menulis `hdmi_group=1` + `hdmi_mode` yang cocok (1080p60 = mode 16),
4. mencadangkan berkas ke `config.txt.bak-ahass`, lalu reboot 2 detik kemudian.

Alternatif dari terminal:

```bash
sudo bash /opt/antrianahass/raspberry/install.sh --resolution=1920x1080 --no-deps
sudo reboot
```

Kalau opsi itu tidak tersedia (bukan Raspberry Pi), halaman admin akan
mengatakannya dan menyarankan `dietpi-config`.

### 5.5 Urutan diagnosis yang cepat

```bash
curl -s http://127.0.0.1:8080/__ahass/api/health; echo   # panel hidup?
ls -l /tmp/.X11-unix/                                    # X hidup? (harus ada X0)
pgrep -af "Xorg|chromium" | head -3                      # proses ada?
sudo bash /opt/antrianahass/raspberry/screen-fix.sh --diagnose
```

Panel **harus** menjawab sebelum layar bisa menampilkan apa pun.

## 6. Hemat memori di 1 GB

Anggaran kasar saat layar berjalan:

| Proses | Perkiraan |
|---|---|
| Node panel | 55–75 MB |
| Chromium (1 renderer, low-end mode) | 180–230 MB |
| LXDE (hanya mode desktop) | 80–120 MB |
| sistem + journald | 120–160 MB |

Sisanya untuk cache. Supaya tidak OOM:

- `MemoryMax=320M` di `ahass-panel.service` sudah membatasi Node.
- `--renderer-process-limit=1` dan `--js-flags=--max-old-space-size=128`
  mencegah Chromium memakai beberapa renderer.
- Aktifkan **zram** (lihat `dietpi-tweaks.md`) — jauh lebih baik daripada
  swapfile di microSD.
- Kalau memakai mode desktop dan masih sesak, pertimbangkan `--mode=kiosk`
  (hemat ±100 MB karena tanpa LXDE).

Menaikkan `--renderer-process-limit` atau `--max-old-space-size` di
`/etc/ahass/chromium-flags.conf` adalah penyebab paling umum layar membeku di
Pi 3 B+.

---

## 7. MicroSD 16 GB tetap awet

Installer sudah menerapkan:

- jurnal systemd maksimal **64 MB** (`/etc/systemd/journald.conf.d/ahass-small.conf`),
- log launcher dirotasi mingguan, maksimal 2 MB × 2 (`/etc/logrotate.d/ahass-kiosk`),
- cache Chromium dibatasi **32 MB** (`--disk-cache-size=33554432`),
- profil Chromium di `~/.config/ahass-kiosk` (mode desktop) atau
  `/var/lib/antrianahass/chromium` (mode kiosk) — keduanya tidak menumpuk
  cache tanpa batas.

Tambahan manual:

```bash
sudo journalctl --vacuum-size=64M
sudo apt-get clean
```

Hindari swapfile di microSD; pakai zram (bawaan DietPi).

---

## 8. Widget ulasan Google (kotak 3)

Widget ulasan adalah aplikasi terpisah di port **3000**. Di Pi 3 B+ aplikasi
Node tambahan itu ikut memakan 60–120 MB RAM, jadi pertimbangkan dulu:

```bash
# cek apakah widget sudah berjalan
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/loader.js
```

- **200** → tempel potongan `<script>` di admin seperti di Compute Stick.
- **000 / kosong** → widget belum dipasang. Aplikasinya ada di repo
  `nhs-den/ulasan-google`; pemasangnya ada di repo ini:

```bash
sudo bash /opt/antrianahass/deploy/install-ulasan.sh --dir ~/ulasan-google-main
```

Kalau RAM terasa sesak, kosongkan kotak 3 (mode ulasan **off**) — panel tetap
berjalan normal tanpa widget.

---

## 9. Memperbarui tanpa pemasangan ulang

```bash
cd ~/antrianahass
git pull
sudo bash raspberry/install.sh --no-deps
```

`/var/lib/antrianahass` (konfigurasi, logo, password admin) **tidak disentuh**,
dan service akan di-restart dengan kode baru. Untuk memperbarui hanya sebagian:

```bash
sudo rsync -a --exclude data --exclude .git ~/antrianahass/ /opt/antrianahass/
sudo systemctl restart ahass-panel
```

---

## 10. Troubleshooting

| Gejala | Penyebab & solusi |
|---|---|
| Layar putih "This site can't be reached" saat boot | Chromium dibuka sebelum panel siap. Launcher di folder ini sudah menunggu `/__ahass/api/health`; kalau log tidak ada, berarti launcher lama masih jalan — `sudo bash raspberry/install.sh --no-deps` ulang lalu reboot. |
| Layar hitam + kursor berkedip (mode kiosk) | tty1 tidak diambil alih. Cek `sudo journalctl -u ahass-kiosk -n 30`; pastikan `dietpi-autostart` = Manual login, dan `xauth` terpasang. Alternatif: `--mode=desktop`. |
| Desktop muncul, Chromium tidak | Baris autostart hilang. Cek `grep ahass ~/.config/lxsession/LXDE/autostart`; harus ada `@/usr/local/bin/ahass-kiosk-desktop.sh`. |
| Layar terbuka dua kali / berkedip | Ada dua entri autostart. `grep -rl ahass-kiosk ~/.config/lxsession ~/.config/autostart`; sisakan satu. |
| Panel hidup, sisi kanan menampilkan halaman "Selamat Datang" | `Path halaman` DDMS belum diisi path board antrean (admin → Web DDMS). |
| Widget ulasan terpotong | Sementara pakai pembungkus `zoom` di kolom kode embed, atau perkecil rasio kotak 3 di Layout. Perbaikan permanen ada di kode `lib/ulasan-page.js`. |
| Chromium OOM / layar membeku | Turunkan `--max-old-space-size` (mis. 96) dan pastikan zram aktif: `zramctl`, `free -m`. |
| `ahass-panel` gagal start | `sudo journalctl -u ahass-panel -n 40 --no-pager`; biasanya Node < 18 atau port 8080 dipakai proses lain (`ss -ltnp \| grep 8080`). |
| Panel lambat setelah beberapa hari | Timer harian 03:00 seharusnya menangani. Restart manual: `sudo systemctl restart ahass-panel`. |

---

## 11. Menghapus

```bash
sudo bash ~/antrianahass/raspberry/uninstall.sh         # unit dihapus, data tetap
sudo bash ~/antrianahass/raspberry/uninstall.sh --purge # hapus data & pengguna ahass
```

---

## 12. Catatan kompatibilitas

- Diuji secara struktur untuk DietPi arm64 (bookworm) dan Debian 12.
- Node minimal **v18**; DietPi bookworm membawa v18 sehingga tidak perlu
  NodeSource.
- Chromium harus dari paket distro (`chromium` / `chromium-browser`);
  versi Snap tidak dipakai karena tidak bisa dijalankan tanpa desktop penuh.
- Kalau suatu saat mode kiosk bermasalah di Pi, mode desktop adalah jalur
  yang sudah terbukti di perangkat produksi.
