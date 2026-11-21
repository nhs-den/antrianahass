# Panel Display AHASS — Munjul Motor

Aplikasi layar informasi untuk **Intel Compute Stick (DietPi / Debian)**.
Menampilkan **web DDMS di 70% layar kanan** dengan **login otomatis**, serta
**panel 30% di kiri** berisi 5 kotak: jam & tanggal, logo, ulasan Google,
gambar dari sosmed, dan video.

Dirancang seringan mungkin: server **Node.js tanpa satu pun dependensi**,
frontend HTML/CSS/JS murni tanpa framework, iframe video hanya dimuat saat
tampil, dan animasi dibatasi pada `opacity` agar CPU/GPU tetap dingin.

```
┌───────────────────────────┬──────────────────────────────────────────────┐
│  KOTAK 1  Jam & tanggal   │                                              │
├───────────────────────────┤                                              │
│  KOTAK 2  Logo            │            WEB DDMS  (70%)                   │
├───────────────────────────┤         login otomatis, same-origin          │
│  KOTAK 3  Ulasan Google   │                                              │
├───────────────────────────┤                                              │
│  KOTAK 4  Gambar sosmed   │                                              │
├───────────────────────────┤                                              │
│  KOTAK 5  Video           │                                              │
└───────────────────────────┴──────────────────────────────────────────────┘
        30%                                   70%
```

---

## 1. Fitur

| Bagian | Isi |
|---|---|
| Kotak 1 | Jam realtime (format 24 jam / AM-PM, opsional detik) + tanggal Indonesia + indikator koneksi DDMS |
| Kotak 2 | Logo yang bisa diganti dari admin + nama bengkel + slogan |
| Kotak 3 | Ulasan Google (rating, jumlah ulasan, ulasan bergantian, foto profil) — 3 mode sumber data |
| Kotak 4 | Slideshow gambar dari link (Instagram/Facebook/Drive/URL gambar), bisa tambah & hapus dari admin |
| Kotak 5 | Video YouTube / Reels / Facebook / TikTok / Vimeo / MP4, bergantian otomatis |
| Kanan 70% | Web DDMS lewat reverse proxy + login otomatis (user & password disimpan terenkripsi) |
| Admin | `/admin` — ganti user/password DDMS, logo, link ulasan, tambah/hapus kotak 4 & 5, atur tata letak |
| Lain-lain | Responsif (landscape, portrait, layar kecil), perubahan admin langsung terlihat tanpa restart, tanpa database |

---

## 2. Kebutuhan

- Intel Compute Stick (x86_64, RAM 2 GB sudah cukup) — juga jalan di mini PC/Intel NUC
- Raspberry Pi 3 B+ (DietPi, microSD 16 GB) — lihat [`raspberry/README.md`](raspberry/README.md)
- STB Amlogic S905X/S905W/S912 (Armbian/ophub) — lihat [`stb/README.md`](stb/README.md)
- **PC sebagai server + STB sebagai layar (LAN)** — lihat [`pc/README.md`](pc/README.md)
- DietPi (v10.x) atau Debian 12/Ubuntu 22.04+
- Node.js **v18+** (`apt install nodejs`)
- Chromium (`apt install chromium`)
- Monitor HDMI + jaringan internet untuk DDMS

Pemakaian memori terukur: **server panel ±45–60 MB**, Chromium kiosk ±180–260 MB,
total di bawah 400 MB.

---

## 3. Instalasi di DietPi

> **Raspberry Pi 3 B+?** Jangan pakai `deploy/install.sh`. Gunakan pemasang
> khusus Pi yang sudah menyetel memori 1 GB dan microSD 16 GB:
> `sudo bash raspberry/install.sh` — panduan lengkap di
> [`raspberry/README.md`](raspberry/README.md).

> **STB Amlogic ber-Armbian (ophub)?** Cukup satu perintah:
> `curl -fsSL https://raw.githubusercontent.com/nhs-den/antrianahass/main/stb/one-click.sh | sudo bash`
> — pemasang, uji layar, dan perbaikan otomatis sampai gambar muncul.
> Detail: [`stb/README.md`](stb/README.md).

> **Mau satu PC melayani beberapa STB?** Server cukup dipasang di PC:
> `sudo bash pc/install.sh` (Linux) atau `powershell -ExecutionPolicy Bypass -File .\pc\windows\install.ps1` (Windows 10),
> lalu tiap STB hanya menampilkan `http://IP-PC:8080/`.
> Detail: [`pc/README.md`](pc/README.md).

```bash
# 1. masuk ke perangkat (SSH)
ssh root@<ip-compute-stick>

# 2. ambil aplikasi
cd /root
git clone https://github.com/nhs-den/antrianahass.git
cd antrianahass

# 3. pasang semuanya (paket, layanan, layar kiosk)
sudo bash deploy/install.sh
```

Skrip pemasang akan:

1. memasang `nodejs`, `chromium`, `xserver-xorg`, `xinit`, `unclutter`, font;
2. membuat pengguna sistem `ahass` (server) dan `kiosk` (layar);
3. menyalin aplikasi ke `/opt/antrianahass`, data ke `/var/lib/antrianahass`;
4. memasang 3 layanan systemd: `ahass-panel`, `ahass-kiosk`, `ahass-restart.timer`;
5. menjalankan server + membuka Chromium fullscreen di `tty1`;
6. menampilkan **password admin** di akhir proses.

> **DietPi:** bila desktop/LXDE ikut menyala otomatis, jalankan `dietpi-autostart`
> dan pilih **Manual / Console** supaya tidak bentrok dengan layar kiosk.
>
> **BIOS:** aktifkan *"Restore AC Power Loss = Power On"* agar kiosk menyala
> sendiri setelah listrik mati.

### Sudah punya folder lama + folder baru?

Bila versi sebelumnya ada di `~/ahass` (dijalankan manual / belum lewat
`install.sh`) dan versi baru ada di `~/antrianahass`, jangan langsung hapus
folder lama — konfigurasi (alamat DDMS, user/password, logo, kotak 4 & 5)
kemungkinan masih ada di `~/ahass/data/`.

```bash
# 1. lihat apa yang sedang berjalan
systemctl status ahass-panel ahass-kiosk --no-pager
ss -ltnp | grep -E ':8080|:3000'

# 2. migrasikan konfigurasi lama + pasang versi baru (satu perintah)
sudo bash ~/antrianahass/deploy/migrate.sh --from ~/ahass

# 3. setelah panel baru terbukti jalan, folder lama boleh dibuang
mv ~/ahass ~/ahass-lama
```

`migrate.sh` akan: mencari `config.json`/`secret.key`/logo pada instalasi lama,
menyalinnya ke `/var/lib/antrianahass` (dengan cadangan), menghentikan proses
panel lama yang masih memakai port 8080 (dengan konfirmasi), lalu memasang
versi baru. Tambahkan `--dry-run` untuk melihat rencananya tanpa mengubah apa pun.

> Hasil ekstrak ZIP **bukan** repo git. `deploy/update.sh` tetap bisa dipakai
> (hanya melewati langkah `git pull`), tapi untuk update berikutnya lebih mudah
> pakai `git clone https://github.com/nhs-den/antrianahass.git` lalu `git pull`.

### Menjalankan widget ulasan-google sebagai layanan (port 3000)

Kotak ulasan mode *snippet* membutuhkan service `ulasan-google` hidup di port 3000
setiap kali perangkat menyala. Ada pemasang otomatis yang mendeteksi jenis
aplikasinya (Node / PHP / Python / `start.sh`):

```bash
sudo bash deploy/install-ulasan.sh --dir ~/ulasan-google-main
# uji:  curl -I http://127.0.0.1:3000/loader.js
```

Skrip ini memasang dependensi bila perlu, membuat `ulasan-google.service`
(restart otomatis, jalan sebagai pemilik folder), lalu memverifikasi
`/loader.js` membalas 200. Gunakan `--dry-run` untuk melihat perintah start yang
dideteksi sebelum dipasang.

### Keduanya menyala bersamaan (panel + widget ulasan)

Sejak 1.3.0 panel **menjalankan sendiri** aplikasi ulasan-google sehingga tidak
ada terminal kedua yang perlu dibuka:

- Admin → **Ulasan Google → Layanan ulasan (port 3000)**:
  status hijau/merah, tombol **Jalankan sekarang**, **Hentikan**,
  **Pasang autostart (systemd)**, dan isian **folder aplikasi**
  (mis. `/home/den/ulasan-google-main`; kosongkan agar dicari otomatis).
- Centang **Jalankan otomatis bersama panel** → tiap kali panel menyala
  (termasuk setelah reboot) widget ikut dinyalakan; kalau widget gagal,
  panel antrian tetap jalan.
- Untuk autostart yang tahan reboot tanpa bergantung pada panel:

```bash
sudo bash deploy/enable-ulasan-autostart.sh              # folder dicari otomatis
sudo bash deploy/enable-ulasan-autostart.sh --dir /home/den/ulasan-google-main
```

Perintah di atas memasang `ulasan-google.service` **dan** drop-in pada
`ahass-panel.service` (`Wants=`/`After=`) sehingga keduanya mulai berdampingan
saat boot, tapi kegagalan widget ulasan tidak pernah menggagalkan panel.
Installer `raspberry/install.sh` dan `stb/install.sh` menjalankan langkah ini
otomatis bila folder `ulasan-google*` ditemukan (lewati dengan `--no-ulasan`).

Cek cepat:

```bash
systemctl status ahass-panel ulasan-google
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/loader.js   # 200 = siap
journalctl -u ulasan-google -n 20 --no-pager
```

### Menjalankan tanpa instalasi (mode uji)

```bash
npm start            # http://localhost:8080
npm run doctor       # cek kesehatan instalasi
npm run mock         # (opsional) DDMS tiruan untuk menguji auto-login
```

---

## 4. Halaman admin

Buka `http://<ip-kiosk>:8080/admin`.

Password pertama kali dibuat otomatis dan ditulis ke:

```
/var/lib/antrianahass/ADMIN-PASSWORD.txt
```

(ditampilkan juga di console saat server pertama kali dijalankan). Ganti password
melalui menu **Keamanan**.

### Menu yang tersedia

| Menu | Fungsi |
|---|---|
| **Ringkasan** | Status server, RAM, koneksi DDMS, tombol *Tes koneksi* & *Tes login otomatis* |
| **Web DDMS** | Alamat web, path halaman, user & password untuk login otomatis, reload otomatis |
| **Logo** | Unggah logo baru (PNG/JPG/WEBP/SVG), pakai URL, atau kembalikan ke bawaan |
| **Ulasan Google** | Pilih sumber ulasan, isi URL/Place ID/API key, tes ambil ulasan |
| **Kotak 4 · Gambar** | Tambah / hapus / urutkan gambar |
| **Kotak 5 · Video** | Tambah / hapus / urutkan video |
| **Tampilan** | Lebar panel kiri (20–60%), jeda rotasi, tema, format jam, sembunyikan kursor |
| **Tampilan → Pas layar** | Skala panel 50–100% + tombol geser ◀▶▲▼ (4 px/klik), **realtime**: layar kiosk bergeser saat tombol ditekan; tombol Batal mengembalikan |
| **Tampilan → Resolusi** | Set mode HDMI dari admin (Pi): 1080p/720p/1360x768/1600x900… lalu reboot otomatis |
| **Keamanan** | Ganti password admin |

Semua perubahan **langsung diterapkan ke layar kiosk** lewat Server-Sent Events —
tidak perlu restart layanan.

---

## 5. Login otomatis DDMS

Login di dalam iframe lintas-domain tidak mungkin dilakukan browser (same-origin
policy). Karena itu panel memakai **reverse proxy**: halaman DDMS dimuat melalui
`http://localhost:8080/...`, sehingga:

- halaman DDMS berada pada origin yang sama dengan panel → skrip kecil boleh
  mengisi form login;
- cookie sesi DDMS tersimpan di browser kiosk dan otomatis ikut terkirim;
- header `X-Frame-Options` / CSP dibuang, `SameSite=None; Secure` diubah menjadi
  `SameSite=Lax` supaya cookie tetap valid di koneksi HTTP lokal;
- URL absolut ke host DDMS ditulis ulang agar tetap melewati proxy
  (termasuk `fetch`, `XMLHttpRequest`, `WebSocket`, dan `EventSource`);
- WebSocket di-proxy juga, jadi fitur realtime DDMS tetap berjalan.

### Cara mengisi

1. Admin → **Web DDMS**
2. Alamat web: `https://web-h2-cbr.daya-dms.id` (tanpa `/ddms`)
3. Path halaman: `/ddms`
4. Centang **Login otomatis**, isi **username** dan **password**, lalu **Simpan**
5. Klik **Tes login otomatis** — panel mencoba login dari sisi server dan
   menampilkan langkah-langkahnya (field yang terdeteksi, cookie yang diterima).

### Bila login otomatis gagal

Panel mendeteksi field secara otomatis (`input[type=password]`, nama field yang
mengandung `user/email/nik/login`, tombol submit pertama). Bila form DDMS memakai
komponen khusus, isi **Pengaturan lanjutan**:

| Isian | Contoh |
|---|---|
| Selector username | `#username` atau `input[name="userid"]` |
| Selector password | `input[type="password"]` |
| Selector tombol login | `button.login-btn` |

Selector memakai sintaks CSS biasa. Setelah disimpan, muat ulang panel
(`systemctl restart ahass-kiosk`) atau tunggu reload otomatis.

Password DDMS **tidak** disimpan sebagai teks biasa: dienkripsi AES-256-GCM
dengan kunci lokal `/var/lib/antrianahass/secret.key` dan hanya dikirim ke
browser sekali pakai lewat token berumur 3 menit.

---

## 6. Widget ulasan Google

**Sejak 1.3.1 widget ulasan menyala otomatis** — tidak perlu memasang aplikasi
tambahan dan tidak perlu folder `ulasan-google`:

1. Panel membuka port **3000** dan menyajikannya sendiri:
   `/loader.js` (penggambar ulasan di kotak ke-3) dan `/reviews.json` (data).
2. Isi sumber datanya sekali di admin → **Ulasan Google**:
   - **URL JSON ulasan** (paling mudah, mis. endpoint JSON ulasan Google), atau
   - **Google Places API**: API key + Place ID / nama tempat.
3. Tekan **Uji ambil ulasan sekarang** untuk memastikan datanya terbaca.

Kalau port 3000 sudah dipakai aplikasi `ulasan-google` terpisah (atau kolom
**Kode embed** / **Host** diisi), panel memakai aplikasi itu dan membiarkan
widget bawaannya diam. Tidak ada yang perlu diubah di sisi kiosk.

Ada 4 cara memasang widget di kotak ke-3. **Kalau Anda hanya punya snippet
`loader.js` dari `ulasan-google`, pakai mode nomor 1.**

| Mode | Yang dibutuhkan | Kapan dipakai |
|---|---|---|
| **1. Widget ulasan (bawaan/snippet)** | URL JSON ulasan **atau** kode embed `<script>…loader.js…</script>` | **Bawaan panel** (port **3000** disediakan sendiri) — paling mudah |
| 2. JSON service | URL endpoint JSON | Bila `ulasan-google` menyediakan API JSON |
| 3. Google Places API | API key + Place ID | Tanpa service tambahan, langsung ke Google |
| 4. Embed halaman | URL halaman siap pakai | Bila `ulasan-google` punya halaman HTML sendiri |

### Mode 1 — tempel snippet `loader.js` (rekomendasi)

Snippet dari `ulasan-google` bentuknya seperti ini:

```html
<script>(function(){var p=document.currentScript.parentNode;function l(){var s=document.createElement('script');s.async=true;s.src='http://'+(location.hostname||'127.0.0.1')+':3000/loader.js?kiosk=1';s.onerror=function(){s.remove();setTimeout(l,3000);};p.appendChild(s);}l();})();</script>
```

Langkah pemasangan:

1. Jalankan aplikasi `ulasan-google` di perangkat (biasanya `node …` atau Docker)
   sehingga melayani **port 3000**.
2. Buka admin → **Ulasan Google** → pilih
   **“Widget ulasan-google — tempel snippet loader.js”**.
3. Tempel snippet di kolom **Kode embed**, lalu **Simpan**.
   (Boleh juga dikosongkan: panel akan membuat snippet yang sama otomatis dari
   isian **Port 3000**, **Path `/loader.js`**, **Query `kiosk=1`**.)
4. Klik **Buka pratinjau widget** untuk memastikan tampil, lalu lihat panel kiosk.

Catatan penting:

- Snippet memakai `location.hostname`, jadi bila panel dibuka dari
  `http://127.0.0.1:8080` widget akan memanggil `http://127.0.0.1:3000/loader.js`.
  Artinya **service ulasan-google harus berjalan di perangkat yang sama**
  (Compute Stick itu sendiri).
  Bila service ada di komputer lain, isi **Host service** (mis. `192.168.1.20`)
  atau ganti `location.hostname` pada snippet menjadi IP tersebut.
- Widget dijalankan **di dalam iframe** (`/__ahass/ulasan`) supaya CSS/JS-nya
  tidak merusak tata letak panel, dan sebaliknya.
- Bila service belum siap saat kiosk menyala, snippet otomatis mencoba ulang
  tiap 3 detik; kotak menampilkan pesan “Widget ulasan belum termuat” sampai
  service hidup.
- **Muat ulang kotak ulasan** (menu yang sama, bawaan 15–30 menit) membuat
  widget diambil ulang agar ulasan baru ikut tampil. Isi `0` untuk mematikan.

> Catatan: repo `nhs-den/ulasan-google` bersifat privat, jadi panel memakai
> adapter generik. Untuk mencoba tanpa service asli, jalankan
> `npm run mock:widget` (port 3000) — kotak ke-3 akan menampilkan widget tiruan.

### Mode 2 — JSON service

Isi **URL JSON ulasan**, mis. `https://ulasan.contoh.id/api/reviews?place=…`.
Panel menerima bentuk JSON yang fleksibel:

```json
{
  "place_name": "AHASS Munjul Motor",
  "rating": 4.7,
  "user_ratings_total": 213,
  "maps_url": "https://maps.google.com/…",
  "reviews": [
    {
      "author_name": "Budi Santoso",
      "profile_photo_url": "https://…",
      "rating": 5,
      "relative_time_description": "2 minggu lalu",
      "text": "Servis cepat dan ramah…"
    }
  ]
}
```

Nama field alternatif juga dikenali (`author`, `text.text`, `stars`, `time`,
`userRatingCount`, `data.reviews`, `result.reviews`, dan seterusnya). Endpoint
dipanggil dari server, jadi tidak terkena CORS.

### Mode 3 — Google Places API

1. Buat API key di Google Cloud Console, aktifkan **Places API (New)**.
2. Isi **Place ID** (`ChIJ…`) atau nama tempat (`AHASS Munjul Motor`).
3. Isi **API key**.

Panel memanggil `places.googleapis.com` dari server (API key tidak pernah
dikirim ke browser) dan menyimpan hasilnya sesuai isian **Cache (menit)**.

### Mode 4 — Embed halaman

Bila `ulasan-google` punya halaman HTML siap pakai, isi **URL halaman embed**
dan halaman itu ditampilkan langsung di kotak ke-3.

Tombol **Tes ambil ulasan** menampilkan hasil parsing (rating, jumlah ulasan,
3 ulasan pertama) untuk mode 2 dan 3.

## 7. Kotak 4 (gambar) dan Kotak 5 (video)

Cukup tempel link — jenis media dikenali otomatis:

| Sumber | Contoh link | Tampil sebagai |
|---|---|---|
| Gambar langsung | `https://situs.com/foto.jpg` | gambar (cover) |
| Instagram post/reel | `https://www.instagram.com/p/xxxx/` | embed Instagram |
| Facebook post/video | `https://www.facebook.com/.../videos/...` | embed Facebook |
| YouTube (video/shorts) | `https://youtu.be/xxxx` | embed YouTube (autoplay, mute, loop) |
| TikTok | `https://www.tiktok.com/@x/video/123` | player TikTok |
| Vimeo | `https://vimeo.com/123456789` | player Vimeo |
| Google Drive | `https://drive.google.com/file/d/ID/view` | preview Drive |
| File video | `https://situs.com/video.mp4` | `<video>` autoplay loop |

- Jumlah item tidak dibatasi (disarankan ≤ 10 per kotak agar ringan).
- Item bergantian sesuai **Jeda ulasan & gambar** / **Jeda video** di menu Tampilan.
- Panel hanya memuat satu iframe aktif; iframe lama dilepas dari DOM sehingga
  CPU tidak terbebani banyak video sekaligus.
- Tombol ↑ ↓ untuk mengatur urutan, ✕ untuk menghapus.

---

### Alamat panel di layar

Di bawah tulisan status (**Antrian Terhubung**) tampil **IP perangkat saja**,
mis. `200.100.100.111` (tanpa port, agar ringkas dan mudah dibaca dari jauh).
Itu alamat yang dipakai STB/PC lain untuk membuka panel; diambil dari
`/__ahass/api/health` sehingga otomatis berubah bila IP berubah (DHCP).
URL lengkap (`http://IP:8080/`) ada pada tooltip baris tersebut.

### Tata letak otomatis (semua resolusi)

Tidak ada pilihan resolusi dan tidak ada tombol geser manual. Panel menyesuaikan
diri sendiri:

- **16:9 / 16:10 / ultrawide** → dua kolom (panel kiri + DDMS).
- **4:3 dan layar potret** → panel kiri pindah ke atas DDMS, isi panel 2 kolom.
- **Layar kecil / pendek** → padding, teks, dan jumlah baris ulasan mengecil
  otomatis.
- **DDMS** diukur lalu diskalakan supaya seluruh halamannya masuk kotak
  (`--stage-fit`), dihitung ulang setiap kali ukuran layar berubah. Header/menu
  DDMS tidak lagi terpotong.

Di admin tersisa dua pengaturan yang perlu: **lebar panel kiri** (20–60%) dan
**skala tampilan** (50–100%, untuk TV yang memotong tepi/overscan). Bila layar
kiosk tidak ikut berubah, ada baris **“Layar kiosk: terhubung”** di kartu yang
sama — kalau tertulis *tidak terhubung*, jalankan
`sudo systemctl restart ahass-kiosk`.

## 8. Perintah harian

```bash
systemctl status ahass-panel ahass-kiosk   # status
systemctl restart ahass-panel              # muat ulang server (konfigurasi tetap)
systemctl restart ahass-kiosk              # muat ulang layar kiosk
journalctl -u ahass-panel -f               # log server
journalctl -u ahass-kiosk -f               # log Chromium

sudo -u ahass AHASS_DATA_DIR=/var/lib/antrianahass \
  node /opt/antrianahass/scripts/reset-password.js   # reset password admin

node /opt/antrianahass/scripts/doctor.js   # pemeriksaan kesehatan
```

### Memperbarui aplikasi (tanpa install ulang)

Tidak perlu instalasi ulang. Kode dan data dipisah:

| Lokasi | Isi | Saat update |
|---|---|---|
| `/opt/antrianahass` | kode program | **ditimpa** versi baru |
| `/var/lib/antrianahass` | `config.json`, password admin, `secret.key`, logo unggahan | **tidak disentuh** |

```bash
# di Raspberry Pi, folder hasil `git clone` ada di /opt/antrianahass
cd /opt/antrianahass
sudo bash deploy/update.sh

# di Intel Compute Stick (folder lama), sesuaikan:
#   cd /root/antrianahass
```

Agar `git pull` di skrip itu berhasil tanpa menanyakan username/password,
sekali saja jalankan:

```bash
gh auth setup-git          # memakai login `gh auth login` yang sudah ada
# atau, bila memakai SSH:
git -C /opt/antrianahass remote set-url origin git@github.com:nhs-den/antrianahass.git
```

`deploy/update.sh` melakukan: `git pull` → salin kode baru → restart panel & layar
kiosk (paket apt tidak dipasang ulang, jadi aman walau internet sedang lambat).
Setara dengan perintah manual berikut bila ingin lebih terkendali:

```bash
cd /root/antrianahass && git pull
sudo bash deploy/install.sh --no-deps
sudo systemctl restart ahass-kiosk        # agar Chromium memuat panel versi baru
```

Setelah update, cek versi di **admin → Ringkasan** (atau `curl -s localhost:8080/__ahass/api/config`).
Bidang konfigurasi baru otomatis ditambahkan dengan nilai bawaan — isian lama
(alamat DDMS, user/password, logo, kotak 4 & 5) tetap seperti sebelumnya.

> Jangan pakai `deploy/uninstall.sh --purge` untuk update — perintah itu menghapus
> folder data beserta konfigurasi.

**Lepas aplikasi:**

```bash
sudo bash deploy/uninstall.sh           # layanan dilepas, data disimpan
sudo bash deploy/uninstall.sh --purge   # hapus aplikasi + data
```

---

### `git clone` private repo gagal: "Password authentication is not supported"

> **DietPi minimal tidak punya `ssh-keygen`/`ssh`** (`ssh-keygen: command not found`,
> `cannot run ssh`). Semua cara berbasis SSH baru bisa dipakai setelah:
> `sudo apt update && sudo apt install -y openssh-client`

**Cek dulu apakah `gh` benar-benar punya sesi login untuk user yang sedang dipakai:**

```bash
gh auth status                 # sebagai dietpi
sudo gh auth status            # sebagai root (dipakai `sudo git clone`)
```

Kalau yang satu bilang *"You are not logged into any GitHub hosts"*, login-nya
berada di user lain. Ulangi di user yang dipakai, misal:

```bash
sudo gh auth login             # bila ingin `sudo git clone` bekerja
sudo gh auth setup-git
```

**Cara tercepat tanpa git/SSH (paling cocok untuk kiosk):** unduh ZIP lewat
browser (tombol **Code → Download ZIP**), lalu timpa folder lama.

**Bila `sudo gh auth status` sudah "Logged in" (cara paling cepat):**

```bash
sudo gh config set git_protocol https    # sesi Anda tadi diset ke ssh
sudo gh auth setup-git                   # tulis credential helper di /root/.gitconfig
sudo git clone https://github.com/nhs-den/antrianahass.git /opt/antrianahass
```

Bila masih ditanya username, pakai token yang sudah tersimpan di gh:

```bash
sudo git clone https://$(sudo gh auth token)@github.com/nhs-den/antrianahass.git /opt/antrianahass
sudo git -C /opt/antrianahass remote set-url origin https://github.com/nhs-den/antrianahass.git
```

**Dengan Personal Access Token (repo privat):** buat token di
<https://github.com/settings/tokens> (scope `repo`), lalu:

```bash
sudo git clone https://<TOKEN>@github.com/nhs-den/antrianahass.git /opt/antrianahass
# setelah selesai, simpan remote tanpa token agar tidak tertinggal di config:
sudo git -C /opt/antrianahass remote set-url origin https://github.com/nhs-den/antrianahass.git
```


GitHub **tidak menerima password akun** untuk operasi git. Dua pilihan:

```bash
# 1) Paling mudah: setelah `gh auth login`, sambungkan gh ke git (sekali saja)
gh auth setup-git
sudo git clone https://github.com/nhs-den/antrianahass.git /opt/antrianahass

# 2) Tanpa git sama sekali (paling aman untuk perangkat kiosk):
#    unduh ZIP lalu timpa folder
cd /tmp
wget -O ahass.zip https://codeload.github.com/nhs-den/antrianahass/zip/refs/heads/main
unzip -q ahass.zip -d /tmp/ahass-baru
sudo rm -rf /opt/antrianahass
sudo mv /tmp/ahass-baru/antrianahass-main /opt/antrianahass
sudo bash /opt/antrianahass/raspberry/install.sh --no-deps
```

- **Jangan** mengetik token/password di prompt `Username for 'https://github.com'` —
  itulah yang menyebabkan `Invalid username or token`.
- `gh auth login` menyimpan sesi untuk user biasa; `sudo git ...` berjalan sebagai
  root dan **tidak** memakai sesi tersebut. Karena itu pakai `gh auth setup-git`
  (mengisi credential helper), SSH key, atau ZIP.
- ZIP `refs/heads/main` tidak memerlukan login bila repo bersifat publik; untuk
  repo privat unduh ZIP lewat browser (tombol **Code → Download ZIP**) lalu
  unggah ke perangkat (`scp`/flashdisk).

### Memulihkan setelah `/opt/antrianahass` terhapus

Data di `/var/lib/antrianahass` (config, password admin, logo) **tidak ikut terhapus**.
Setelah kode kembali ke `/opt/antrianahass`:

```bash
sudo bash /opt/antrianahass/raspberry/install.sh --no-deps
```

Installer akan memakai ulang konfigurasi yang sudah ada — tidak perlu mengisi
ulang alamat DDMS, user/password, logo, maupun kotak 4 & 5.

## 9. Tips performa di Intel Compute Stick

Sudah diterapkan otomatis:

- server tanpa dependensi (tidak ada `node_modules`), memori ±50 MB;
- HTML/CSS/JS disajikan lokal tanpa build step dan tanpa framework;
- jam diperbarui sekali per detik hanya pada dua node teks;
- iframe video hanya satu yang hidup pada satu waktu;
- rotasi berhenti saat layar tidak aktif (`visibilitychange`);
- Chromium dijalankan dengan cache 64 MB, `renderer-process-limit=3`,
  `max-old-space-size=256`, dan pembaruan latar dimatikan.

Bila masih terasa berat (mis. video tersendat):

```bash
# turunkan resolusi layar, contoh 1366x768
sudo cp /etc/X11/xorg.conf /etc/X11/xorg.conf.bak 2>/dev/null || true

# atau kurangi jumlah video & jangan pakai video full HD
```

Bisa juga menambahkan flag Chromium sendiri:

```bash
sudo systemctl edit ahass-kiosk
# [Service]
# Environment="CHROMIUM_FLAGS=--disable-gpu"
```

---

## 10. Struktur berkas

```
antrianahass/
├── server.js                 # HTTP server, router, API admin, SSE
├── lib/
│   ├── config.js             # konfigurasi + enkripsi rahasia
│   ├── auth.js               # sesi admin
│   ├── proxy.js              # reverse proxy DDMS + injeksi login
│   ├── reviews.js            # adapter ulasan Google (3 mode)
│   ├── ddms.js               # tes koneksi & tes login
│   ├── static.js             # penyaji file statis
│   ├── ulasan-page.js        # halaman iframe widget ulasan-google (loader.js)
│   └── util.js
├── public/
│   ├── index.html            # panel kiosk (5 kotak + iframe DDMS)
│   ├── style.css
│   ├── app.js
│   ├── admin.html / admin.css / admin.js
│   ├── patch.js              # menyelaraskan URL di dalam iframe DDMS
│   ├── autologin.js          # pengisi form login DDMS
│   └── assets/logo.png
├── raspberry/                # pemasang khusus Raspberry Pi 3 B+ (DietPi, 16 GB)
│   ├── install.sh / uninstall.sh
│   ├── kiosk-desktop.sh      # launcher desktop: tunggu panel + watchdog
│   ├── chromium-flags.conf   # flag hemat RAM 1 GB
│   ├── units/                # ahass-panel, ahass-kiosk, ahass-restart
│   └── README.md / dietpi-tweaks.md
├── pc/                       # server di PC + pemasang layar STB (LAN)
│   ├── install.sh            # server PC (systemd)
│   ├── doctor.js             # cek jalur PC→STB, cetak IP yang benar
│   ├── windows/              # pemasang Windows 10: Node+service+autostart
│   └── client/               # layar STB: kiosk ke http://IP-PC:8080/
├── stb/                      # pemasang khusus STB Amlogic (Armbian/ophub)
│   ├── one-click.sh          # curl | sudo bash
│   ├── install.sh            # pasang + uji layar
│   ├── screen-fix.sh         # eskalasi perbaikan layar (GPU/root/legacy)
│   ├── smoke-test.sh         # diagnosa panel & layar
│   ├── units/                # ahass-panel, ahass-kiosk, ahass-restart
│   └── README.md
├── deploy/
│   ├── install.sh / update.sh / migrate.sh / uninstall.sh
│   ├── install-ulasan.sh     # layanan widget ulasan-google (port 3000)
│   ├── enable-ulasan-autostart.sh  # ulasan + panel menyala bersamaan saat boot
│   ├── fix-kiosk.sh          # diagnosis + perbaikan layar kiosk (X/Chromium)
│   ├── start-kiosk.sh
│   ├── ahass-panel.service
│   ├── ahass-kiosk.service
│   └── ahass-restart.{service,timer}
├── scripts/
│   ├── reset-password.js
│   ├── doctor.js
│   ├── mock-ddms.js          # DDMS tiruan untuk uji auto-login
│   └── mock-reviews.js       # endpoint JSON ulasan tiruan
└── data/                     # dibuat otomatis saat pertama jalan
    ├── config.json
    ├── secret.key
    └── uploads/
```

---

## 11. Troubleshooting

| Gejala | Penyebab & solusi |
|---|---|
| Layar hitam / hanya kursor | Chromium belum ada atau X gagal start. Jalankan **`sudo bash deploy/fix-kiosk.sh`** (memasang chromium/xauth, menguji, dan bila perlu memakai mode root). Cek juga `journalctl -u ahass-kiosk -n 50`. |
| `ahass-kiosk` exited status=1 berulang | Biasanya Chromium tidak terpasang (skrip berhenti dalam milidetik) atau Xorg tidak boleh membuka `/dev/tty1`. `fix-kiosk.sh` menangani keduanya. |
| "Belum tersambung ke DDMS" | Kiosk tidak bisa internet atau alamat salah. Cek menu Ringkasan → **Tes koneksi**. |
| Halaman DDMS tampil tapi tidak login | Jalankan **Tes login otomatis**; periksa user/password; isi selector manual. |
| Login berhasil lalu kembali ke halaman login | Situs memakai cookie `SameSite=None; Secure` + HTTPS; panel sudah mengubahnya ke `Lax`. Bila masih gagal, coba aktifkan **Abaikan sertifikat SSL tidak valid** hanya jika sertifikat DDMS memang bermasalah. |
| Ulasan tidak muncul | Mode `off`? URL JSON/API key salah? Lihat **Tes ambil ulasan**. |
| “Widget ulasan belum termuat” | Service `ulasan-google` belum jalan di port 3000. Cek `curl http://127.0.0.1:3000/loader.js`, lalu pastikan service otomatis start saat boot. |
| Widget jalan di laptop tapi tidak di kiosk | Snippet memakai `location.hostname`; isi **Host service** dengan IP perangkat yang menjalankan `ulasan-google`. |
| Widget tampil di panel ber-HTTPS tapi tidak di HTTP (atau sebaliknya) | Konten `http://` diblokir di halaman `https://`. Untuk kiosk selalu gunakan `http://127.0.0.1:8080` (sudah bawaan). |
| Video YouTube hitam | Video dibatasi pemiliknya (embed dimatikan), atau butuh login. Ganti dengan video lain. |
| Foto Instagram tidak tampil | Link post biasanya butuh embed; pastikan link berbentuk `/p/…` atau `/reel/…`. |
| Jam/tanggal salah | Set zona waktu: `sudo timedatectl set-timezone Asia/Jakarta`. |
| Layar mati sendiri | DPMS. `start-kiosk.sh` sudah mematikan; bila monitor punya *auto-off*, matikan di menu monitor. |
| Admin minta login terus | Cookie terblokir; buka lewat `http://ip:8080/admin` (bukan `https`). |
| Punya folder lama `ahass` dan baru `antrianahass` | Jalankan `sudo bash ~/antrianahass/deploy/migrate.sh --from ~/ahass`; jangan hapus folder lama sebelum panel baru terbukti jalan. |
| Apakah update perlu install ulang? | Tidak. Jalankan `sudo bash deploy/update.sh`; konfigurasi di `/var/lib/antrianahass` tetap utuh. |
| Setelah update tampilan tidak berubah | Restart kiosk: `sudo systemctl restart ahass-kiosk` (aset teks sudah dibuat `no-cache`, jadi biasanya cukup reload). |
| Lupa password admin | `sudo -u ahass AHASS_DATA_DIR=/var/lib/antrianahass node /opt/antrianahass/scripts/reset-password.js` |

---

## 12. Keamanan

- Panel ditujukan untuk **jaringan lokal bengkel**. Jangan buka port 8080 ke internet
  tanpa reverse proxy ber-HTTPS + autentikasi tambahan.
- Password admin di-hash dengan `scrypt`; password DDMS dienkripsi AES-256-GCM.
- Sesi admin: cookie `HttpOnly` + `SameSite=Lax`, berakhir 12 jam, maksimal
  8 percobaan login per 10 menit per alamat IP.
- Service berjalan sebagai pengguna `ahass` dengan `NoNewPrivileges`, `ProtectHome`,
  dan `MemoryMax=384M`.

---

## Lisensi

MIT © AHASS Munjul Motor
