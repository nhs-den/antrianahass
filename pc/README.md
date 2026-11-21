# Panel AHASS di PC — layar STB memanggil PC lewat LAN

Folder ini untuk skema **satu PC menjadi server, banyak STB menjadi layar**.

```
        PC (Linux/Windows)                     STB (Armbian / Android)
   ┌──────────────────────────┐           ┌───────────────────────────┐
   │  ahass-pc.service        │  HTTP     │  Chromium kiosk           │
   │  node server.js :8080    │◄──────────│  http://IP-PC:8080/       │
   │  /var/lib/antrianahass   │  LAN      │  (tanpa server apa pun)   │
   └──────────────────────────┘           └───────────────────────────┘
        konfigurasi, logo,                    hanya menampilkan
        ulasan, DDMS, cache
```

Semua data ada di PC. STB hanya menampilkan alamat — jadi:

- STB tidak perlu diinstal aplikasi, cukup browser kiosk;
- ganti logo/DDMS/ulasan cukup **sekali di PC**, semua layar ikut berubah;
- STB yang mati/rusak bisa diganti apa saja yang punya browser;
- PC harus hidup selama jam operasional.

---

## 1. Sisi PC

### Linux (dianjurkan)

Di PC, dari dalam repo:

```bash
git clone https://github.com/nhs-den/antrianahass.git ~/antrianahass
cd ~/antrianahass
sudo bash pc/install.sh
```

Lalu periksa jalurnya:

```bash
node pc/doctor.js
```

Contoh keluaran sehat:

```
[ ok ] alamat LAN PC                 192.168.1.10
[ ok ] server panel (loopback)       v1.1.0 · 41 MB · ddms auto
[ ok ] server dari alamat LAN        192.168.1.10:8080 menjawab
[ ok ] port terbuka                  8080
─────────────────────────────────────────────────────────────
Jalur PC siap. Di STB cukup arahkan ke http://192.168.1.10:8080/
```

Opsi:

```bash
sudo bash pc/install.sh --port=9090      # ganti port
sudo bash pc/install.sh --no-deps        # perbarui kode saja (git pull dulu)
sudo bash pc/install.sh --no-firewall    # jangan sentuh ufw/firewalld
sudo bash pc/install.sh --dry-run
```

Aman dijalankan berulang. `/var/lib/antrianahass` (DDMS, password admin, logo,
ulasan) tidak pernah ditimpa.

### Windows

Buka **PowerShell sebagai Administrator**, dari folder repo:

```powershell
.\pc\windows\install-service.ps1
```

Skrip itu menyalin aplikasi ke `C:\Program Files\antrianahass`, menyimpan data
di `C:\ProgramData\antrianahass`, mendaftarkan **Windows Service `AhassPanel`**
(restart otomatis bila mati), membuka port 8080 di firewall, lalu memverifikasi
`/__ahass/api/health`.

Opsi:

```powershell
.\pc\windows\install-service.ps1 -Port 9090    # ganti port
.\pc\windows\install-service.ps1 -Remove       # lepas service
Get-Content C:\ProgramData\antrianahass\logs\panel.log -Tail 40   # log
```

Butuh Node.js 18+ dari [nodejs.org](https://nodejs.org) (centang *Add to PATH*).
Tidak perlu NSSM — service memakai wrapper `powershell.exe` bawaan Windows.

### Setelah server jalan

1. Buka `http://IP-PC:8080/admin` dari browser **di PC** (nyaman untuk mengetik).
2. Isi Web DDMS (alamat, user, password) dan **Path halaman** board antrean.
3. Unggah logo, tempel kode ulasan Google, isi kotak 4–5.
4. Simpan. Semua STB langsung memakai konfigurasi baru.

Password admin ada di:

- Linux: `/var/lib/antrianahass/ADMIN-PASSWORD.txt`
- Windows: `C:\ProgramData\antrianahass\ADMIN-PASSWORD.txt`

---

## 2. Sisi STB (Armbian)

Di STB, cukup satu perintah — **tidak perlu repo, tidak perlu Node**:

```bash
curl -fsSL https://raw.githubusercontent.com/nhs-den/antrianahass/main/pc/client/install.sh \
  | sudo bash -s -- --pc=192.168.1.10
```

Atau kalau repo sudah ada di STB:

```bash
git clone https://github.com/nhs-den/antrianahass.git ~/antrianahass
sudo bash ~/antrianahass/pc/client/install.sh --pc=192.168.1.10
```

Yang dilakukan skrip itu:

1. membuat/menemukan pengguna layar (tidak menjalankan browser sebagai root
   kecuali terpaksa),
2. memasang `chromium`, `xserver-xorg`, `xinit`, `x11-xserver-utils`,
   `x11-apps` (untuk `xwd`), `unclutter`,
3. memasang `/usr/local/bin/ahass-pc-kiosk.sh` + `ahass-pc-wait-panel.sh`,
4. menulis unit `ahass-pc-kiosk.service` dengan URL PC,
5. mematikan kiosk mode mandiri (`ahass-kiosk` / `ahass-panel`) bila ada —
   dua unit kiosk akan berebut `tty1`,
6. menguji apakah PC benar-benar menjawab **dari STB**,
7. menguji layar: unit jalan → X ada → Chromium hidup → isi layar dibaca `xwd`.

Opsi:

```bash
sudo bash pc/client/install.sh --pc=192.168.1.10 --port=9090
sudo bash pc/client/install.sh --pc=192.168.1.10 --dry-run
sudo bash pc/client/install.sh --pc=192.168.1.10 --no-deps     # tanpa apt
sudo bash pc/client/install.sh --pc=192.168.1.10 --no-fix      # tanpa uji layar
```

### Kalau IP PC berubah

Cukup jalankan ulang dengan IP baru (profil Chromium & data lain tetap):

```bash
sudo bash pc/client/install.sh --pc=192.168.1.20
```

Atau sunting satu baris tanpa installer:

```bash
sudo sed -i 's#.*#http://192.168.1.20:8080/#' /etc/ahass-client/panel-url
sudo systemctl restart ahass-pc-kiosk
```

Lebih baik lagi: beri **IP statis / DHCP reservation** untuk PC di router, lalu
tidak perlu menyentuh STB lagi.

### STB masih Android?

Lihat [`client/windows-autostart.md`](client/windows-autostart.md) — pakai
Fully Kiosk Browser dengan Start URL `http://IP-PC:8080/`.

---

## 3. Diagnosa

| Di mana | Perintah |
|---|---|
| PC (Linux) | `node pc/doctor.js --port=8080` |
| PC (Windows) | `node "C:\Program Files\antrianahass\pc\doctor.js"` |
| STB | `sudo bash pc/client/screen-fix.sh` |
| STB, tanpa mengubah apa pun | `sudo bash pc/client/screen-fix.sh --no-content` |
| STB, log layar | `journalctl -u ahass-pc-kiosk -n 40 --no-pager` |
| STB, log Chromium | `sudo tail -40 /var/log/ahass-kiosk-client.log` |

Urutan masalah yang paling sering, dari yang paling mungkin:

1. **PC tidak menjangkau STB** — `curl` dari STB:
   `curl -s http://IP-PC:8080/__ahass/api/health`. Kalau gagal: firewall PC.
2. **STB memakai `127.0.0.1`** — harus IP PC, bukan localhost.
3. **IP PC berubah** karena DHCP → ulangi installer dengan IP baru.
4. **GPU STB bermasalah** → `screen-fix.sh` menambahkan `--disable-gpu`.
5. **Xorg tidak boleh buka VT** → `screen-fix.sh` langkah 2 (legacy + root).

---

## 4. Kalau STB masih menampilkan versi lama

STB-client tidak menjalankan kode aplikasi, hanya menampilkan. Jadi
**memperbarui panel cukup di PC**:

```bash
cd ~/antrianahass && git pull && sudo bash pc/install.sh --no-deps
```

STB akan memuat ulang halaman pada siklus muat berikutnya (atau restart unit
layar sekali: `sudo systemctl restart ahass-pc-kiosk`).

---

## 5. Struktur folder

```
pc/
├── install.sh                  # pemasang server PC (Linux)
├── doctor.js                   # cek jalur PC↔STB, cetak alamat LAN yang benar
├── units/ahass-pc.service      # Node :8080, HOST=0.0.0.0, MemoryMax=768M
├── windows/
│   ├── install-service.ps1     # server sebagai Windows Service + firewall
│   └── runner.ps1              # wrapper proses untuk service
└── client/
    ├── install.sh              # pemasang layar STB (tanpa server)
    ├── uninstall.sh            # lepas layar STB
    ├── kiosk.sh                # menjalankan Chromium kiosk ke URL PC
    ├── wait-panel.sh           # ExecStartPre: tunggu PC /health agar tak putih
    ├── screen-fix.sh           # eskalasi perbaikan layar (0→3) + diagnosa
    ├── chromium-flags.conf     # flag hemat memori untuk STB
    ├── ahass-pc-kiosk.service  # unit layar STB
    └── windows-autostart.md    # kalau STB masih Android
```

---

## 6. Catatan keamanan & beban

- Panel terbuka di LAN tanpa login untuk halaman tampilan. Halaman **`/admin`
  tetap butuh password**. Jangan teruskan port 8080 ke internet.
- Satu PC melayani beberapa STB sekaligus: tiap STB hanya mengambil HTML/aset
  statis + streaming DDMS lewat proxy. Untuk 5–10 layar, CPU PC hampir tidak
  terasa; yang naik hanya trafik LAN.
- Beban terberat ada di STB (Chromium merender), bukan di PC. Karena itu STB
  tetap memakai `chromium-flags.conf` yang hemat memori.
- Kalau DDMS memblokir karena banyak sesi dari satu IP, gunakan
  `node scripts/mock-ddms.js` untuk uji beban, atau jalankan server di PC yang
  IP-nya memang diizinkan DDMS.
