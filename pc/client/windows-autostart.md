# Kalau STB-nya masih Android (belum diganti Armbian)

Rencana utama folder `pc/` menganggap STB sudah ber-Armbian. Kalau STB masih
**Android TV box** apa adanya, jangan pasang `pc/client/install.sh` — yang
dipakai adalah aplikasi kiosk Android yang membuka satu URL:

| Aplikasi | Cara | Catatan |
|---|---|---|
| **Fully Kiosk Browser** | Play Store / APK | Paling lengkap: autostart, kiosk, reload otomatis bila gagal muat. Gratis versi dasar. |
| **KioskBrowser** / **Webview Kiosk** | Play Store | Ringan, hanya satu URL. |
| **Wallpaper + shortcut** | bawaan | Kalau butuh seadanya: buat shortcut Chrome ke alamat, taruh di home launcher. |

Pengaturan yang perlu diisi di Fully Kiosk Browser:

1. **Web Content → Start URL**: `http://IP-PC:8080/`
2. **Web Content → Enable JavaScript**: aktif (panel butuh JS)
3. **Web Content → Reload on Idle / on Network Error**: 30 detik
   (ini pengganti `wait-panel.sh` — kalau PC belum siap saat boot, Android akan
   mencoba lagi sendiri)
4. **Device Management → Launch on Boot**: aktif
5. **Device Management → Keep Screen On**: aktif
6. **Settings → Kiosk Mode**: aktif, PIN 4 digit
7. **Advanced Web Settings → Clear Cache on Reload**: matikan
   (supaya sesi DDMS tidak hilang)

Catatan penting untuk STB Android:

- **Jangan pakai `127.0.0.1`** — di Android itu menunjuk ke STB sendiri.
  Selalu `http://IP-PC:8080/`.
- Android box yang ikut reboot akan kembali ke launcher kalau Fully Kiosk tidak
  punya izin "Display over other apps". Beri izin itu saat pertama dibuka.
- Kalau box di-root, `am start` bisa dipakai lewat `init.d`, tapi Fully Kiosk
  sudah cukup untuk hampir semua kasus.
- Hemat daya: matikan animasi di **Developer options → Window/Transition/Animator
  scale = off**. Panel jadi terasa lebih ringan.
