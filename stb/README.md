# Panel AHASS di STB Amlogic (Armbian / ophub)

Pemasang khusus untuk **STB Android TV box** yang sudah diganti Linux —
Amlogic **S905X / S905W / S912** dengan **Armbian (ophub)**, RAM 1–2 GB.
Tujuannya satu: **satu perintah, lalu layar benar-benar menampilkan panel.**

Aplikasinya sama dengan versi Compute Stick / Raspberry Pi (satu proses Node,
tanpa dependensi, tanpa build step). Bedanya: STB tidak punya desktop, GPU-nya
Mali-450 di kernel mainline sering bermasalah, dan Xorg tidak diizinkan membuka
VT sebagai pengguna biasa. Tiga hal itulah yang ditangani otomatis di sini.

---

## 1. Satu perintah

Dari SSH ke STB (Armbian sudah terpasang, sudah ada internet):

```bash
curl -fsSL https://raw.githubusercontent.com/nhs-den/antrianahass/main/stb/one-click.sh | sudo bash
```

Skrip itu akan:

1. memasang `git` + `curl` bila belum ada,
2. mengambil repo ke `/opt/antrianahass-src` (klon atau perbarui),
3. menjalankan `stb/install.sh`: paket, pengguna, unit systemd, flag Chromium,
4. **menguji layar** dan memperbaikinya bertahap sampai gambar muncul,
5. mencetak ringkasan + password admin.

Kalau berhasil, akhirnya akan tampil:

```
[ ok ] Panel AHASS sudah TAMPIL di layar TV/monitor.
```

Selesai. Tinggal buka `http://IP-STB:8080/admin` dan isi konfigurasi.

Sudah punya repo di STB? Tidak perlu `one-click.sh`:

```bash
git clone https://github.com/nhs-den/antrianahass.git ~/antrianahass
sudo bash ~/antrianahass/stb/install.sh
```

---

## 2. Opsi pemasang

```bash
sudo bash stb/install.sh                      # pasang + perbaiki layar (default)
sudo bash stb/install.sh --no-fix             # pasang saja, layar diuji manual nanti
sudo bash stb/install.sh --no-deps            # lewati apt-get (perbarui kode saja)
sudo bash stb/install.sh --user=kiosk         # pengguna yang menjalankan layar
sudo bash stb/install.sh --port=8080          # ganti port panel
sudo bash stb/install.sh --resolution=1920x1080  # paksa resolusi HDMI (menulis /boot/uEnv.txt)
sudo bash stb/install.sh --dry-run            # lihat rencana, tidak mengubah sistem
```

Aman dijalankan berulang. `/var/lib/antrianahass` (konfigurasi, logo, password
admin) tidak pernah ditimpa.

---

## 3. Bagaimana layar "dipaksa" tampil

`install.sh` memanggil `screen-fix.sh`, yang menguji layar secara nyata —
bukan hanya "unit aktif". Pemeriksaannya: unit `running`, socket X
`/tmp/.X11-unix/X0` ada, proses Chromium memuat URL panel, lalu **isi layar
dibaca** lewat `xwd` dan dihitung piksel bukan-hitamnya. Layar hitam tidak
dianggap berhasil.

Eskalasi otomatis:

| Langkah | Perubahan | Untuk kasus |
|---|---|---|
| 0 | apa adanya | Chromium sebagai pengguna `kiosk`, GPU Mali aktif |
| 1 | `+ --disable-gpu` | compositing Mali-450 gagal (paling sering) → rendering software |
| 2 | `+ xserver-xorg-legacy`, `Xwrapper.config`, layar sebagai root | Xorg tidak boleh membuka VT sebagai non-root |
| 3 | menyerah + diagnosa lengkap | sisanya: DTB, resolusi, driver, memori |

Hasil perbaikan dicatat di `/var/lib/antrianahass/.stb-screen-fix`
(`langsung`, `nogpu`, `root`, atau `gagal`). Perbaikan diterapkan sebagai
drop-in systemd, jadi bisa dicabut kapan saja:

```bash
sudo bash stb/screen-fix.sh --reset      # hapus stb-nogpu.conf / stb-root.conf
```

Diagnosa ulang kapan saja:

```bash
sudo bash stb/smoke-test.sh
```

Contoh keluaran sehat:

```
[ ok ] panel (ahass-panel)          running
[ ok ] HTTP health                  {"ok":true,"version":"1.1.0",…}
[ ok ] layar (ahass-kiosk)          running
[ ok ] X server (:0)                socket ada
[ ok ] Chromium                     1234 pid
[ ok ] isi layar                    piksel bukan-hitam: 918273
[ ok ] memori                       1240 MB bebas dari 1975 MB
[ ok ] GPU (/dev/dri/card0)         ada
```

---

## 4. Struktur folder

```
stb/
├── one-click.sh             # curl | sudo bash (ambil repo + jalankan install.sh)
├── install.sh               # pemasang utama: paket, pengguna, unit, flag, uji layar
├── screen-fix.sh            # eskalasi 0→3 + verifikasi piksel (xwd)
├── smoke-test.sh            # uji kondisi panel & layar (tidak mengubah apa pun)
├── uninstall.sh             # lepas (--purge untuk hapus data)
├── chromium-flags.conf      # flag Chromium, disesuaikan otomatis ke RAM
├── units/
│   ├── ahass-panel.service  # Node :8080 (MemoryMax=384M)
│   ├── ahass-kiosk.service  # tty1 + xinit + ExecStartPre tunggu panel
│   ├── ahass-restart.service / .timer   # restart harian 03:00
├── scripts/wait-panel.sh    # ExecStartPre: cegah halaman putih saat boot
├── journald-ahass-small.conf / sysctl-ahass-stb.conf
└── README.md
```

---

## 5. Yang dilakukan otomatis

- **Paket**: `nodejs`, `chromium`, `xserver-xorg`, `xinit`, `xauth`,
  `x11-xserver-utils`, `x11-apps` (untuk `xwd`), `unclutter`, `fonts-dejavu-core`.
- **Pengguna**: sistem `ahass` untuk server; pengguna layar dicari dari
  `SUDO_USER` → `kiosk` → `armbian` → `dietpi` → uid ≥ 1000. Kalau STB hanya
  punya `root` (khas ophub), installer **membuat user `kiosk`** — Chromium tidak
  dijalankan sebagai root kecuali langkah 2 eskalasi menuntutnya.
- **Flag Chromium**: RAM ≥ 1,8 GB → 2 renderer + heap 256 MB; di bawah itu →
  1 renderer + heap 128 MB. Nilainya ditanam ke unit sebagai
  `Environment="CHROMIUM_FLAGS=…"` (kutip wajib, kalau tidak systemd hanya
  memakai flag pertama).
- **Anti layar putih saat boot**: `ExecStartPre=ahass-wait-panel.sh` menunggu
  `/__ahass/api/health` (maks 120 s) sebelum Chromium dibuka.
- **MicroSD/eMMC awet**: jurnal maks 64 MB, cache Chromium 64 MB, restart harian
  03:00 membersihkan memori.

---

## 6. Setelah layar tampil

Buka `http://IP-STB:8080/admin`:

1. **Web DDMS** — alamat, username, password. Setelah login berhasil, salin
   **path board antrean** dari address bar ke kolom *Path halaman* (tanpa ini,
   tampilan kembali ke halaman "Selamat Datang" saat halaman dimuat ulang).
2. **Logo** — unggah `logo-ahass-munjul-motor.png`.
3. **Ulasan Google** — tempel potongan `<script>…loader.js?kiosk=1</script>`
   apa adanya (mode *script*).
4. **Kotak 4 & 5** — daftar gambar/video.
5. **Layout** — rasio kotak kiri (default 1 / 1 / 1.9 / 1.15 / 1.55).

Password admin:

```bash
sudo cat /var/lib/antrianahass/ADMIN-PASSWORD.txt
```

---

## 7. Tuning di STB (RAM 2 GB, GPU Mali)

**Resolusi HDMI.** Kalau gambar meluber atau terlalu kecil:

```bash
sudo bash /opt/antrianahass/stb/install.sh --resolution=1920x1080 --no-deps
sudo reboot
grep -n "video=HDMI" /boot/uEnv.txt      # cek hasilnya (backup: /boot/uEnv.txt.bak-ahass)
```

Resolusi lebih rendah sering memperbaiki STB yang GPU-nya lemah — 1280x720
lebih ringan untuk Chromium software rendering.

**Kalau layar patah-patah / lag.** Pastikan `--disable-gpu` aktif (langkah 1
eskalasi), dan pertimbangkan `--renderer-process-limit=1`:

```bash
sudo sed -i 's/^--renderer-process-limit=.*/--renderer-process-limit=1/' \
  /etc/ahass/chromium-flags.conf
sudo bash /opt/antrianahass/stb/install.sh --no-deps
```

**Kalau ingin kembali ke GPU (hardware rendering)** setelah kernel/driver
diperbaiki:

```bash
sudo bash /opt/antrianahass/stb/screen-fix.sh --reset
sudo systemctl restart ahass-kiosk
```

**Kalau ingin Chromium tidak dijalankan sebagai root** (walau sudah tampil):

```bash
sudo bash /opt/antrianahass/stb/screen-fix.sh --reset     # hapus drop-in root
```

---

## 8. Chromium dari SNAP (image berbasis Ubuntu)

Armbian berbasis Ubuntu tidak punya `chromium` apt — yang terpasang adalah
snap. Installer mendeteksinya, memberi peringatan, dan memindahkan profil
Chromium ke `~/.config/ahass-kiosk` (snap menolak menulis di luar home), tetapi
hasilnya lebih lambat dan butuh ruang ±1 GB.

Kalau bisa memilih, pakai **image Armbian berbasis Debian (bookworm)**.

---

## 9. Troubleshooting

| Gejala | Solusi |
|---|---|
| `[fail] Layar belum bisa menampilkan panel setelah 3 langkah` | Skrip sudah mencetak 40 baris jurnal + error Xorg. Kirim keluaran itu. Coba dulu `--resolution=1280x720`. |
| Layar hitam, unit aktif | `sudo bash stb/smoke-test.sh` → lihat baris "isi layar". Kalau gelap: `sudo bash stb/screen-fix.sh`. |
| Layar menampilkan halaman putih "site can't be reached" | Panel belum siap saat Chromium dibuka — `ahass-wait-panel.sh` sudah mencegahnya; pastikan `ExecStartPre` tidak dihapus: `systemctl cat ahass-kiosk \| grep -A1 ExecStartPre`. |
| Panel jalan, DDMS menampilkan "Selamat Datang" | Isi *Path halaman* DDMS di admin (path board antrean). |
| Tampilan patah-patah | `--disable-gpu` + resolusi 1280x720; pantau suhu `cat /sys/class/thermal/thermal_zone0/temp` |
| Chromium tidak bisa start sebagai user | Cek `journalctl -u ahass-kiosk`; biasanya profil tidak bisa ditulis → pastikan `AHASS_PROFILE_DIR` dimiliki user layar. |
| `Unit ahass-kiosk tidak ditemukan` saat `screen-fix.sh` | Jalankan `sudo bash stb/install.sh --no-deps` lebih dulu. |
| DTB salah (layar mati total, termasuk teks konsol) | Itu level boot, bukan aplikasi: perbaiki `FDT=` di `/boot/uEnv.txt` untuk model box Anda. |

---

## 10. Memperbarui & menghapus

```bash
# perbarui kode saja (konfigurasi aman)
curl -fsSL https://raw.githubusercontent.com/nhs-den/antrianahass/main/stb/one-click.sh | sudo bash -s -- --no-deps

# atau dari repo lokal
cd ~/antrianahass && git pull && sudo bash stb/install.sh --no-deps
```

```bash
sudo bash stb/uninstall.sh             # hapus unit & layar, data tetap
sudo bash stb/uninstall.sh --purge     # hapus data + user ahass
```

---

## 11. Catatan kompatibilitas

- Ditulis untuk Armbian ophub (Debian/Ubuntu, arm64) di S905X/S905W/S912.
- Juga jalan di Debian 12 x86_64/arm64 apa pun (dengan peringatan), karena
  isinya systemd + X + Chromium.
- Butuh Node ≥ 18 dan Chromium apt; keduanya dipasang installer.
- Belum diuji pada perangkat STB fisik — kalau ada kegagalan, `smoke-test.sh`
  + `journalctl` memberi cukup konteks untuk diperbaiki.
