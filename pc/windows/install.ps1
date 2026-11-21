# Panel AHASS - pemasang untuk PC Windows 10 (server untuk layar STB di LAN).
#
# SATU PERINTAH (PowerShell sebagai Administrator, dari folder repo):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\pc\windows\install.ps1
#
# Yang dikerjakan:
#   1. memasang paket yang diperlukan  -> git (portable), Node.js LTS (resmi)
#   2. menyalin aplikasi ke           -> C:\Program Files\antrianahass
#   3. menyimpan data (DDMS, logo) di -> C:\ProgramData\antrianahass
#   4. membuat autostart              -> Windows Service "AhassPanel"
#                                        (+ shortcut Startup sebagai cadangan)
#   5. membuka port di Windows Firewall
#   6. memverifikasi /__ahass/api/health
#   7. membuat shortcut "Panel AHASS" di Desktop
#
# Opsi:
#   -Port 8080             ganti port panel
#   -NoDeps                lewati pemasangan Node/git (sudah ada)
#   -NoFirewall            jangan sentuh Windows Firewall
#   -SkipStartupShortcut   hanya pakai Windows Service (tanpa shortcut Startup)
#   -RepoUrl <url>         sumber repo selain default
#   -Force                 timpa profil Chromium? (tidak dipakai di server)
#   -Remove                lepas service + shortcut + firewall, data tetap
#   -Purge                 seperti -Remove, tapi data ikut dihapus
#
# Aman dijalankan berulang. Data di C:\ProgramData\antrianahass tidak ditimpa.

[CmdletBinding()]
param(
  [int]$Port = 8080,
  [string]$ServiceName = "AhassPanel",
  [string]$RepoUrl = "https://github.com/nhs-den/antrianahass.git",
  [string]$Ref = "main",
  [switch]$NoDeps,
  [switch]$NoFirewall,
  [switch]$SkipStartupShortcut,
  [switch]$Remove,
  [switch]$Purge
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # Invoke-WebRequest jauh lebih cepat

# --------------------------------------------------------------------- util
function Info($m) { Write-Host "[pc] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[ ok ] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[warn] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[fail] $m" -ForegroundColor Red; exit 1 }
function Step($n, $m) { Write-Host ""; Write-Host "[$n] $m" -ForegroundColor White }

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $pr = New-Object Security.Principal.WindowsPrincipal($id)
  return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-NodeExe {
  $c = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  foreach ($p in @(
      (Join-Path $Env:ProgramFiles "nodejs\node.exe"),
      (Join-Path ${Env:ProgramFiles(x86)} "nodejs\node.exe"),
      "C:\nodejs\node.exe")) {
    if ($p -and (Test-Path $p)) { return $p }
  }
  return $null
}

function Get-GitExe {
  $c = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  foreach ($p in @(
      (Join-Path $Env:ProgramFiles "Git\cmd\git.exe"),
      (Join-Path $Env:ProgramFiles "Git\bin\git.exe"),
      "C:\Program Files\Git\cmd\git.exe")) {
    if (Test-Path $p) { return $p }
  }
  return $null
}

function Add-PathEverywhere([string]$dir) {
  if (-not $dir -or -not (Test-Path $dir)) { return }
  $paths = [Environment]::GetEnvironmentVariable("Path", "Machine")
  if ($paths -notlike "*$dir*") {
    [Environment]::SetEnvironmentVariable("Path", "$paths;$dir", "Machine")
    Info "PATH (system) ditambah: $dir"
  }
  if (($Env:Path -split ";") -notcontains $dir) { $Env:Path = "$Env:Path;$dir" }
}

function New-Shortcut([string]$path, [string]$target, [string]$arguments, [string]$desc) {
  $dir = Split-Path -Parent $path
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $ws = New-Object -ComObject WScript.Shell
  $sc = $ws.CreateShortcut($path)
  $sc.TargetPath = $target
  $sc.Arguments = $arguments
  $sc.Description = $desc
  $sc.WorkingDirectory = Split-Path -Parent $target
  $sc.IconLocation = "$target,0"
  $sc.Save()
}

# ---------------------------------------------------------------- konstanta
$AppDir  = Join-Path $Env:ProgramFiles "antrianahass"
$DataDir = Join-Path $Env:ProgramData "antrianahass"
$ConfDir = Join-Path $DataDir "conf"
$LogDir  = Join-Path $DataDir "logs"
$EnvFile = Join-Path $ConfDir "pc.env"
$Health  = "http://127.0.0.1:$Port/__ahass/api/health"
$PublicDesk = Join-Path $Env:PUBLIC "Desktop"
$StartupDir = Join-Path $Env:ProgramData "Microsoft\Windows\Start Menu\Programs\StartUp"
$StartupLnk = Join-Path $StartupDir "Panel AHASS.lnk"
$DesktopLnk = Join-Path $PublicDesk "Panel AHASS.lnk"
$WatchdogDir = Join-Path $DataDir "watchdog"
$WatchdogVbs = Join-Path $WatchdogDir "panel-kiosk.vbs"
$RuleName   = "Panel AHASS ($Port)"

Write-Host ""
Write-Host "=============================================================" -ForegroundColor DarkGray
Write-Host " Panel AHASS - pemasang server Windows 10" -ForegroundColor White
Write-Host "=============================================================" -ForegroundColor DarkGray
Write-Host " OS       : $([Environment]::OSVersion.VersionString)"
Write-Host " Host     : $Env:COMPUTERNAME"
Write-Host " Port     : $Port"
Write-Host " Aplikasi : $AppDir"
Write-Host " Data     : $DataDir"

if (-not (Test-Admin)) {
  Die "Jalankan PowerShell sebagai Administrator (klik kanan > Run as administrator)."
}

$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

# =========================================================== lepas (opsional)
if ($Remove -or $Purge) {
  Step 1 "Melepas service, shortcut, dan aturan firewall"
  $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
  if ($svc) {
    if ($svc.Status -eq "Running") { Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue }
    sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 1
    Ok "Service $ServiceName dilepas."
  } else { Info "Service $ServiceName tidak ada." }

  foreach ($f in @($StartupLnk, $DesktopLnk)) {
    if (Test-Path $f) { Remove-Item $f -Force; Ok "Shortcut dihapus: $f" }
  }
  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  if (Test-Path $runKey) {
    Remove-ItemProperty -Path $runKey -Name "PanelAhassWatchdog" -ErrorAction SilentlyContinue
    Ok "Entri autostart watchdog dihapus."
  }
  if (Test-Path $WatchdogVbs) { Remove-Item $WatchdogVbs -Force -ErrorAction SilentlyContinue }
  Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
  Ok "Aturan firewall '$RuleName' dihapus."

  if ($Purge) {
    Info "Menghapus aplikasi dan data…"
    if (Test-Path $AppDir)  { Remove-Item $AppDir -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $DataDir) { Remove-Item $DataDir -Recurse -Force -ErrorAction SilentlyContinue }
    Ok "Aplikasi + data dihapus (-Purge)."
  } else {
    Warn "Data dipertahankan di $DataDir (pakai -Purge untuk menghapus)."
  }
  Write-Host ""
  Ok "Selesai. Panel tidak lagi berjalan otomatis."
  exit 0
}

# ============================================================== 1. paket
Step 1 "Memasang paket yang diperlukan (Node.js, git)"

if ($NoDeps) {
  Info "-NoDeps: pemasangan paket dilewati."
} else {
  $nodeExe = Get-NodeExe
  if ($nodeExe) {
    $v = (& $nodeExe -v).TrimStart("v")
    if ([int]($v.Split(".")[0]) -lt 18) {
      Warn "Node.js v$v terlalu tua (butuh 18+). Akan dipasang LTS di sampingnya."
      $nodeExe = $null
    } else {
      Ok "Node.js v$v sudah ada: $nodeExe"
    }
  }

  if (-not $nodeExe) {
    $arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    Info "Mengambil Node.js LTS (msi, $arch) dari nodejs.org…"
    $msi = Join-Path $Env:TEMP "node-lts-$arch.msi"
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      $idx = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -UseBasicParsing -TimeoutSec 60
      $lts = ($idx | Where-Object { $_.lts -ne $false } | Select-Object -First 1)
      if (-not $lts) { throw "Daftar rilis Node tidak terbaca." }
      $ver = $lts.version
      $url = "https://nodejs.org/dist/$ver/node-$ver-$arch.msi"
      Info "Node.js $ver → $url"
      Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing -TimeoutSec 600
      $sig = Get-AuthenticodeSignature -FilePath $msi
      if ($sig.Status -ne "Valid") { Warn "Tanda tangan MSI: $($sig.Status) (lanjut, sumber resmi nodejs.org)" }
      Info "Memasang Node.js (diam-diam, ±1-2 menit)…"
      $p = Start-Process msiexec.exe -ArgumentList @("/i", "`"$msi`"", "/qn", "/norestart") -Wait -PassThru
      if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { Die "msiexec gagal (kode $($p.ExitCode))." }
      Remove-Item $msi -Force -ErrorAction SilentlyContinue
      # Node MSI menulis PATH mesin; proses ini perlu PATH baru.
      $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                  [Environment]::GetEnvironmentVariable("Path", "User")
      $nodeExe = Get-NodeExe
      if (-not $nodeExe) { Die "Node.js terpasang tetapi node.exe tidak ditemukan. Buka PowerShell baru lalu jalankan ulang." }
      Ok "Node.js $(& $nodeExe -v) terpasang: $nodeExe"
    } catch {
      Die "Gagal memasang Node.js otomatis: $_. Pasang manual dari https://nodejs.org (LTS 20/22, centang 'Add to PATH'), lalu jalankan ulang skrip ini."
    }
  }

  if (-not (Test-Path (Join-Path $AppDir "server.js"))) {
    $gitExe = Get-GitExe
    if (-not $gitExe) {
      Info "git belum ada, mengambil Git for Windows portable (32-bit)…"
      $zip = Join-Path $Env:TEMP "mingit.zip"
      $dest = "C:\ProgramData\antrianahass\git"
      # Nama berkas rilis berubah antar versi, jadi diambil dari API GitHub
      # (tanpa tag: otomatis rilis terbaru). Fallback ke URL yang sudah diketahui.
      $minGitUrl = "https://github.com/git-for-windows/git/releases/latest/download/MinGit-2.47.1-32-bit.zip"
      try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest" `
          -UseBasicParsing -TimeoutSec 60 -Headers @{ "User-Agent" = "ahass-installer" }
        $asset = $rel.assets | Where-Object { $_.name -match "^MinGit-.*-32-bit\.zip$" } | Select-Object -First 1
        if ($asset) { $minGitUrl = $asset.browser_download_url; Info "MinGit: $($asset.name)" }
      } catch {
        Warn "API GitHub tidak terjangkau; memakai URL MinGit bawaan."
      }
      try {
        Invoke-WebRequest -Uri $minGitUrl -OutFile $zip -UseBasicParsing -TimeoutSec 600
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Expand-Archive -Path $zip -DestinationPath $dest -Force
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Add-PathEverywhere (Join-Path $dest "cmd")
        $gitExe = Get-GitExe
        if ($gitExe) { Ok "git portable siap: $gitExe" } else { Warn "git portable gagal disiapkan." }
      } catch {
        Warn "Git portable gagal diambil: $_. Lanjut tanpa git (akan mencoba unduh ZIP repo)."
      }
    } else {
      Ok "git sudah ada: $gitExe"
    }
  } else {
    Info "Aplikasi sudah ada di $AppDir (git tidak diperlukan untuk pembaruan)."
  }
}

$nodeExe = Get-NodeExe
if (-not $nodeExe) { Die "Node.js tidak ditemukan. Pasang dari https://nodejs.org lalu jalankan ulang." }
$nodeVer = (& $nodeExe -v).TrimStart("v")
if ([int]($nodeVer.Split(".")[0]) -lt 18) { Die "Node.js v$nodeVer terlalu tua (butuh 18+)." }
Ok "Node.js v$nodeVer ($nodeExe)"

# ============================================================ 2. sumber kode
Step 2 "Menyiapkan berkas aplikasi di $AppDir"

$src = $null
if (Test-Path (Join-Path $Repo "server.js")) { $src = $Repo; Info "Sumber: folder repo ini ($Repo)" }

if (-not $src) {
  $src = Join-Path $Env:TEMP "antrianahass-src"
  $gitExe = Get-GitExe
  if ($gitExe) {
    if (Test-Path (Join-Path $src ".git")) {
      Info "Memperbarui sumber di $src…"
      & $gitExe -C $src fetch --depth 1 origin $Ref | Out-Null
      & $gitExe -C $src reset --hard FETCH_HEAD | Out-Null
    } else {
      if (Test-Path $src) { Remove-Item $src -Recurse -Force -ErrorAction SilentlyContinue }
      Info "Mengkloning $RepoUrl ($Ref) ke $src…"
      & $gitExe clone --depth 1 --branch $Ref $RepoUrl $src | Out-Null
    }
    if (Test-Path (Join-Path $src "server.js")) { Ok "Sumber siap (git)." }
  }
  if (-not (Test-Path (Join-Path $src "server.js"))) {
    Info "Mengunduh ZIP repo…"
    $zip = Join-Path $Env:TEMP "antrianahass.zip"
    $zipUrl = ($RepoUrl -replace "\.git$", "") + "/archive/refs/heads/$Ref.zip"
    Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing -TimeoutSec 300
    $tmp = Join-Path $Env:TEMP "antrianahass-unzip"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    if (-not $inner) { Die "ZIP repo tidak berisi folder." }
    $src = $inner.FullName
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Ok "Sumber siap (ZIP)."
  }
}

if (-not (Test-Path (Join-Path $src "server.js"))) { Die "Sumber aplikasi tidak ditemukan." }

Info "Menyalin ke $AppDir…"
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
# robocopy: 0-7 = sukses, >=8 = gagal. /MIR membersihkan berkas lama (data ada di DataDir).
$rc = Start-Process robocopy -ArgumentList @(
  "`"$src`"", "`"$AppDir`"", "/MIR", "/XD", ".git", "data", "node_modules",
  "/NFL", "/NDL", "/NJH", "/NJS", "/NP"
) -Wait -PassThru -NoNewWindow
if ($rc.ExitCode -ge 8) { Die "robocopy gagal (kode $($rc.ExitCode))." }

foreach ($d in @($DataDir, $ConfDir, $LogDir, (Join-Path $DataDir "uploads"), (Join-Path $DataDir "logos"))) {
  New-Item -ItemType Directory -Force -Path $d | Out-Null
}
# Aplikasi berjalan sebagai SYSTEM; pastikan SYSTEM bisa menulis data & log.
& icacls.exe $DataDir /grant "SYSTEM:(OI)(CI)F" /T /C /Q | Out-Null
Ok "Aplikasi tersalin; data di $DataDir."

# ==================================================== 3. konfigurasi (env)
Step 3 "Menulis konfigurasi layanan"

@(
  "# Dibuat oleh pc/windows/install.ps1 - jangan diedit saat service berjalan.",
  "PORT=$Port",
  "HOST=0.0.0.0",
  "NODE_ENV=production",
  "AHASS_DATA_DIR=$DataDir",
  "NODE_OPTIONS=--max-old-space-size=512"
) | Set-Content -Path $EnvFile -Encoding ASCII
Ok "Konfigurasi: $EnvFile"

# Service menjalankan node.exe langsung (satu proses, tanpa konsol, tanpa
# proses yatim saat dihentikan). launcher.js membaca conf\pc.env lalu memuat
# server.js dan menulis semua keluaran ke logs\panel.log.
$launcher = Join-Path $AppDir "windows\launcher.js"
if (-not (Test-Path $launcher)) { Die "Launcher tidak ditemukan: $launcher" }
$binPath = "`"$nodeExe`" `"$launcher`""

# ================================================================ 4. autostart
Step 4 "Membuat autostart (Windows Service + shortcut Startup)"

# Service lama dilepas dulu supaya binPath baru dipakai.
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
  Info "Service $ServiceName sudah ada - diperbarui."
  if ($svc.Status -eq "Running") { Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 1
  sc.exe delete $ServiceName | Out-Null
  Start-Sleep -Seconds 1
}

sc.exe create $ServiceName binPath= $binPath start= auto DisplayName= "Panel AHASS (server)" | Out-Null
if ($LASTEXITCODE -ne 0) { Die "Gagal membuat service $ServiceName (kode $LASTEXITCODE)." }
sc.exe description $ServiceName "Panel antrean AHASS - server untuk layar STB di LAN (port $Port)." | Out-Null
# Jangan mati kalau gagal pertama (jaringan belum siap saat boot): ulangi 3x.
sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/15000/restart/60000 | Out-Null
# Beri waktu jaringan sebelum start pertama.
sc.exe config $ServiceName start= delayed-auto | Out-Null
Ok "Service $ServiceName didaftarkan (autostart, restart otomatis, delayed start)."

# Layar penuh di PC ini sendiri (opsional). Dua lapis:
#   - shortcut Startup  : jalan sekali saat login, langsung fullscreen
#   - VBS di Startup    : watchdog ringan yang membuka lagi kalau jendela ditutup
#                           atau Edge crash (dicek tiap 20 detik, tanpa konsol).
if (-not $SkipStartupShortcut) {
  $startUrl = "http://localhost:$Port/"
  $edge = Join-Path ${Env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"
  if (-not (Test-Path $edge)) { $edge = Join-Path $Env:ProgramFiles "Microsoft\Edge\Application\msedge.exe" }
  if (Test-Path $edge) {
    $edgeArgs = "--app=`"$startUrl`" --start-fullscreen --no-first-run --no-default-browser-check " +
                "--disable-features=Translate,msEdgeIdentityFRE --user-data-dir=`"$DataDir\edge-profile`""
    New-Shortcut $DesktopLnk $edge $edgeArgs "Panel AHASS (fullscreen)"

    New-Item -ItemType Directory -Force -Path $WatchdogDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDir "edge-profile") | Out-Null
    # VBS ditulis dengan placeholder yang ditukar setelah here-string,
    # supaya kutip ganda/tanda kurung kurawal PowerShell tidak merusaknya.
    $vbs = @'
' Panel AHASS - watchdog layar penuh (dibuat oleh pc\windows\install.ps1)
' Membuka Edge dalam mode app/fullscreen; kalau ditutup atau crash, dibuka lagi.
Option Explicit
Dim sh, fso, edge, profile, url, args
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
edge    = "__EDGE__"
url     = "__URL__"
profile = "__PROFILE__"
args    = "--app=""" & url & """ --start-fullscreen --no-first-run" & _
          " --no-default-browser-check --user-data-dir=""" & profile & """"

If Not fso.FileExists(edge) Then WScript.Quit

Do
  ' Edge hidup bila kunci profil terkunci oleh prosesnya (tidak butuh tasklist).
  If Not fso.FileExists(profile & "\lockfile") Then
    On Error Resume Next
    sh.Run """" & edge & """ " & args, 1, False
    On Error GoTo 0
    WScript.Sleep 20000
  End If
  WScript.Sleep 20000
Loop
'@
    # VBS harus ANSI/ASCII + CRLF agar wscript.exe lama tidak salah baca.
    $vbs = $vbs.Replace("__EDGE__", $edge).Replace("__URL__", $startUrl).Replace("__PROFILE__", $profile)
    $vbs = $vbs -replace "`r?`n", "`r`n"
    Set-Content -Path $WatchdogVbs -Value $vbs -Encoding ASCII -NoNewline
    $wscript = Join-Path $Env:SystemRoot "System32\wscript.exe"
    New-Shortcut $StartupLnk $wscript "`"$WatchdogVbs`"" "Panel AHASS (fullscreen + watchdog)"

    $auto = New-Object -ComObject WScript.Shell
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    if (-not (Test-Path $runKey)) { New-Item -Path $runKey -Force | Out-Null }
    $auto.SetValue($runKey, "PanelAhassWatchdog", "`"$wscript`" `"$WatchdogVbs`"")
    Ok "Autostart layar PC: Startup shortcut + watchdog VBS, plus entri Run."
  } else {
    Warn "Microsoft Edge tidak ditemukan - tampilan fullscreen di PC dilewati."
    Warn "Panel tetap tersedia di browser: $startUrl"
  }
} else {
  Info "-SkipStartupShortcut: hanya Windows Service yang dipakai (tanpa layar fullscreen)."
}

try { Start-Service $ServiceName } catch { Warn "Start-Service: $($_.Exception.Message)" }

# =============================================================== 5. firewall
Step 5 "Membuka port $Port di Windows Firewall"
if ($NoFirewall) {
  Warn "-NoFirewall: firewall tidak disentuh. Pastikan port $Port terbuka untuk LAN."
} else {
  Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue
  $profiles = @("Private", "Domain")
  try {
    New-NetFirewallRule -DisplayName $RuleName -Direction Inbound -Protocol TCP `
      -LocalPort $Port -Action Allow -Profile $profiles -Group "Panel AHASS" | Out-Null
    Ok "Aturan firewall '$RuleName' dibuat (profil Private + Domain)."
  } catch {
    Warn "Gagal lewat cmdlet, mencoba netsh: $($_.Exception.Message)"
    netsh advfirewall firewall add rule name="$RuleName" dir=in action=allow protocol=TCP localport=$Port | Out-Null
    Ok "Aturan firewall dibuat lewat netsh."
  }
  $pub = Get-NetFirewallProfile -Profile Public -ErrorAction SilentlyContinue
  if ($pub -and $pub.Enabled) {
    Warn "Profil firewall 'Public' aktif. Kalau jaringan PC ditandai 'Public', STB tetap terblokir."
    Warn "Ubah jaringan ke 'Private': Settings > Network & Internet > Wi-Fi > Properties."
  }
}

# ============================================================ 6. verifikasi
Step 6 "Memverifikasi panel"

$ready = $false
for ($i = 1; $i -le 40; $i++) {
  try {
    $r = Invoke-WebRequest -Uri $Health -UseBasicParsing -TimeoutSec 3
    if ($r.StatusCode -eq 200) { $ready = $true; break }
  } catch { }
  Start-Sleep -Seconds 1
  if ($i -eq 1) { Info "Menunggu server menjawab (maks 40 detik)…" }
}

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
  if ($svc.Status -eq "Running") { Ok "Service $ServiceName: $($svc.Status)" }
  else { Warn "Service $ServiceName: $($svc.Status) - cek log $LogDir\panel.log" }
}

if ($ready) { Ok "Server menjawab: $Health" }
else {
  Warn "Server belum menjawab. Periksa:"
  Warn "  Get-Content `"$LogDir\panel.log`" -Tail 40"
  Warn "  Get-Service $ServiceName | Format-List Status,StartType"
}

# ============================================================= 7. ringkasan
$ips = @()
try {
  $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
    Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
    Select-Object -ExpandProperty IPAddress
} catch {
  $ips = (ipconfig | Select-String "IPv4" | ForEach-Object { ($_ -split ":")[1].Trim() })
}

$passFile = Join-Path $DataDir "ADMIN-PASSWORD.txt"

Write-Host ""
Write-Host "=============================================================" -ForegroundColor DarkGray
if ($ready) { Ok "Server panel AHASS siap dipakai STB." } else { Warn "Terpasang, tetapi belum merespons (lihat log di atas)." }
foreach ($ip in $ips) { Write-Host "  Alamat LAN   : http://${ip}:$Port/" -ForegroundColor White }
Write-Host "  Admin        : http://localhost:$Port/admin"
if (Test-Path $passFile) {
  $pw = (Get-Content $passFile -TotalCount 1) -replace "^\s*|\s*$", ""
  if ($pw) { Write-Host "  Password     : $pw" -ForegroundColor Yellow }
}
Write-Host ""
Write-Host "  Autostart    : Windows Service '$ServiceName' (delayed-auto, restart otomatis)"
if (-not $SkipStartupShortcut) { Write-Host "                 + watchdog fullscreen 'Panel AHASS' (Edge --app, buka lagi bila ditutup)" }
Write-Host "  Firewall     : aturan '$RuleName' (profil Private + Domain)"
Write-Host "  Log          : $LogDir\panel.log"
Write-Host "  Diagnosa     : node `"$AppDir\pc\doctor.js`" --port=$Port"
Write-Host "  Lepas        : .\pc\windows\install.ps1 -Remove      (data tetap)"
Write-Host "                 .\pc\windows\install.ps1 -Purge       (data dihapus)"
Write-Host "  Pasang STB   : (di STB) sudo bash pc/client/install.sh --pc=IP-PC"
Write-Host "=============================================================" -ForegroundColor DarkGray
Write-Host ""
Info "Langkah berikutnya: buka http://localhost:$Port/admin di PC, isi DDMS + logo + ulasan."
Write-Host ""
Write-Host "CATATAN: beri PC IP statis / DHCP reservation di router agar STB tidak" -ForegroundColor Yellow
Write-Host "perlu diubah setiap kali PC restart." -ForegroundColor Yellow
Write-Host ""
Write-Host "Bila PowerShell menolak menjalankan skrip, pakai:" -ForegroundColor DarkGray
Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File .\pc\windows\install.ps1" -ForegroundColor DarkGray
