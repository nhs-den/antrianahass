# Windows 10: pasang, autostart, dan perawatan

Panduan singkat untuk PC server. Skrip instalasinya satu:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\pc\windows\install.ps1
```

(Run PowerShell **as Administrator** dari folder repo.)

---

## 1. Apa yang berjalan setelah PC menyala

```
Windows boot
   │
   ├─ (delayed-auto) Windows Service "AhassPanel"  → node launcher.js → server :8080
   │                                                 (tanpa perlu login)
   │
   └─ user login → Startup: watchdog VBS            → Edge --app --start-fullscreen
                    + entri registry Run              (buka lagi bila ditutup/crash)
```

Konsekuensi yang perlu dipahami:

- **STB sudah bisa memuat panel sebelum ada yang login** — server adalah service.
- Layar fullscreen di PC baru muncul setelah **user login**, karena browser butuh
  sesi desktop. Kalau PC tidak dipakai sebagai layar, pakai
  `-SkipStartupShortcut`.
- Kalau PC dipakai sebagai layar 24 jam, matikan **sleep**:
  *Settings → System → Power & sleep → Sleep: Never*, dan
  *Screen: Never*.

---

## 2. Memeriksa kondisi

```powershell
Get-Service AhassPanel | Format-List Name,Status,StartType
Invoke-WebRequest http://localhost:8080/__ahass/api/health -UseBasicParsing | Select -Expand Content
Get-Content C:\ProgramData\antrianahass\logs\panel.log -Tail 30
Get-NetFirewallRule -DisplayName "Panel AHASS (8080)" | Select DisplayName,Enabled,Profile
```

Dari STB (SSH):

```bash
curl -s http://IP-PC:8080/__ahass/api/health   # harus keluar JSON {"ok":true,...}
```

Kalau dari PC jalan tetapi dari STB tidak: **firewall** atau **profil jaringan
Public**. Lihat bagian 5.

---

## 3. Memperbarui aplikasi (tanpa reinstall)

Data tidak tersentuh, service hanya di-restart:

```powershell
cd C:\Users\NAMA-ANDA\antrianahass
git pull
.\pc\windows\install.ps1 -NoDeps
```

Kalau tidak memakai git, unduh ZIP repo terbaru dan jalankan skrip yang sama
dari folder hasil ekstrak — installer akan menyalin ulang berkasnya.

---

## 4. Ganti port

```powershell
.\pc\windows\install.ps1 -Port 9090
```

Lalu di setiap STB:

```bash
sudo bash pc/client/install.sh --pc=IP-PC --port=9090
```

---

## 5. Memakai nama PC, bukan IP

Kalau Anda mengetik nama komputer di STB, misalnya:

```bash
sudo bash pc/client/install.sh --pc=PC-KASIR
```

`install.sh` menguji nama itu, dan kalau tidak menjawab ia mencoba **nama pendek**
(sebelum titik) — karena nama NetBIOS PC bisa berbeda dari nama host. Kalau
keduanya gagal, pakai IP; resolusi nama di STB bergantung pada DNS/router dan
lebih rapuh daripada IP statis.

## 6. Kalau STB menampilkan halaman kosong / "can't be reached"

| Cek | Perintah / lokasi |
|---|---|
| Service hidup? | `Get-Service AhassPanel` |
| Server menjawab lokal? | `curl http://localhost:8080/__ahass/api/health` |
| Port listen di semua antarmuka? | `netstat -ano \| findstr :8080` → harus `0.0.0.0:8080` |
| Firewall | `Get-NetFirewallRule -DisplayName "Panel AHASS (8080)"` |
| Profil jaringan | *Settings → Network & Internet → Status → Properties* → harus **Private** |
| IP PC benar? | `ipconfig` → cocokkan dengan `--pc=` di STB |
| IP berubah? | beri DHCP reservation di router, atau jalankan ulang installer STB |

Menambah aturan firewall manual (kalau `-NoFirewall` dipakai):

```powershell
New-NetFirewallRule -DisplayName "Panel AHASS (8080)" -Direction Inbound `
  -Protocol TCP -LocalPort 8080 -Action Allow -Profile Private,Domain
```

---

## 7. Kalau service gagal start

```powershell
Get-Content C:\ProgramData\antrianahass\logs\panel.log -Tail 40
sc.exe qc AhassPanel          # cek binPath menunjuk node.exe + launcher.js
node "C:\Program Files\antrianahass\pc\doctor.js" --port=8080
```

Penyebab umum:

- **Node.js terpasang setelah service dibuat** → jalankan ulang installer
  (`-NoDeps` tidak cukup; tanpa `-NoDeps` skrip akan menemukan Node yang baru).
- **AV/EDR memblokir** `node.exe` sebagai service → tambahkan pengecualian folder
  `C:\Program Files\antrianahass` dan proses `node.exe`.
- **Port dipakai aplikasi lain** → `netstat -ano | findstr :8080`, ganti port.

Uji manual di luar service (memudahkan melihat error):

```powershell
node "C:\Program Files\antrianahass\windows\launcher.js" --data=C:\ProgramData\antrianahass
```

Hentikan service dulu supaya port tidak bentrok:

```powershell
Stop-Service AhassPanel
```

---

## 8. Matikan / lepas

```powershell
Stop-Service AhassPanel                                  # berhenti sementara
Set-Service AhassPanel -StartupType Manual               # jangan autostart
.\pc\windows\install.ps1 -Remove                         # lepas service+shortcut, data tetap
.\pc\windows\install.ps1 -Purge                          # lepas + hapus data
```

`-Remove` juga menghapus aturan firewall dan entri autostart watchdog, jadi PC
benar-benar kembali seperti semula.

---

## 9. Cadangan

Yang perlu dicadangkan hanya satu folder:

```
C:\ProgramData\antrianahass
├── config.json          # DDMS, layout, kotak 4-5
├── ADMIN-PASSWORD.txt
├── uploads\  logos\     # logo & gambar
└── conf\pc.env          # port
```

Salin ke flashdisk / OneDrive. Memulihkan = hentikan service, timpa folder,
start lagi.
