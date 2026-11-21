# Panel AHASS - pasang server di PC Windows sebagai Windows Service.
#
#   PowerShell (Administrator):
#     .\pc\windows\install-service.ps1                 # pasang + nyalakan
#     .\pc\windows\install-service.ps1 -Port 8080
#     .\pc\windows\install-service.ps1 -Remove         # lepas service
#
# Cara kerja: membuat "wrapper service" (sc.exe, ServiceType own) yang
# menjalankan node.exe dengan skrip runner.ps1. Tanpa NSSM, tanpa dependensi
# tambahan - hanya Node.js yang harus sudah terpasang.
#
# Aman dijalankan berulang: service lama dihentikan dan dilepas dulu.

[CmdletBinding()]
param(
  [int]$Port = 8080,
  [string]$ServiceName = "AhassPanel",
  [string]$DataDir = "C:\ProgramData\antrianahass",
  [switch]$Remove
)

$ErrorActionPreference = "Stop"

function Info($m) { Write-Host "[pc] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[ ok ] $m" -ForegroundColor Green }
function Die($m)  { Write-Host "[fail] $m" -ForegroundColor Red; exit 1 }

$isAdmin = ([Security.Principal.WindowsPrincipal] `
  [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Die "Jalankan PowerShell sebagai Administrator." }

$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$AppDir = Join-Path $Env:ProgramFiles "antrianahass"
$NodeExe = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
if (-not $NodeExe) { Die "Node.js tidak ditemukan di PATH. Pasang Node 18+ dari nodejs.org lalu jalankan ulang." }
$NodeVersion = (& $NodeExe -p "process.versions.node")
if ([int]($NodeVersion.Split(".")[0]) -lt 18) { Die "Node.js v$NodeVersion terlalu tua (butuh 18+)." }

# --------------------------------------------------------------- lepas service
$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
  Info "Service $ServiceName sudah ada - menghentikan dan melepas…"
  sc.exe stop $ServiceName | Out-Null
  Start-Sleep -Seconds 2
  sc.exe delete $ServiceName | Out-Null
  Start-Sleep -Seconds 1
}
if ($Remove) { Ok "Service $ServiceName dilepas."; exit 0 }

# ------------------------------------------------------------------ salin berkas
Info "Menyalin aplikasi ke $AppDir…"
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
# /MIR menghapus berkas lama yang sudah tidak ada di repo; data TIDAK ada di sini.
$rc = Start-Process robocopy -ArgumentList @(
  "`"$Repo`"", "`"$AppDir`"", "/MIR", "/XD", ".git", "data", "node_modules", "/NFL", "/NDL", "/NJH", "/NJS", "/NP"
) -Wait -PassThru -NoNewWindow
if ($rc.ExitCode -ge 8) { Die "robocopy gagal (kode $($rc.ExitCode))." }

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $DataDir "uploads") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $DataDir "logos") | Out-Null
Ok "Aplikasi tersalin."

# ------------------------------------------------------------- konfigurasi env
$ConfDir = Join-Path $DataDir "conf"
New-Item -ItemType Directory -Force -Path $ConfDir | Out-Null
$confFile = Join-Path $ConfDir "pc.env"
@(
  "# Diatur oleh pc/windows/install-service.ps1",
  "PORT=$Port",
  "HOST=0.0.0.0",
  "NODE_ENV=production",
  "AHASS_DATA_DIR=$DataDir",
  "NODE_OPTIONS=--max-old-space-size=512"
) | Set-Content -Path $confFile -Encoding ASCII
Ok "Konfigurasi: $confFile (port $Port)"

# --------------------------------------------------------------- pasang service
# Runner yang dijalankan sebagai service: membaca pc.env lalu menjalankan server.
$runner = Join-Path $AppDir "windows\runner.ps1"
if (-not (Test-Path $runner)) { Die "Runner tidak ditemukan: $runner" }

$psExe = Join-Path $Env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$binPath = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$runner`""

Info "Mendaftarkan service $ServiceName…"
sc.exe create $ServiceName binPath= $binPath start= auto DisplayName= "Panel AHASS (server)" | Out-Null
sc.exe description $ServiceName "Panel antrean AHASS - server untuk layar STB di LAN (port $Port)." | Out-Null
# Restart otomatis bila proses mati: reset 1 hari, restart 5 detik, 3 percobaan.
sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null
Start-Service $ServiceName
Ok "Service $ServiceName berjalan."

# -------------------------------------------------------------------- firewall
Info "Membuka port $Port di Windows Firewall…"
$ruleName = "Panel AHASS ($Port)"
Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Private,Domain | Out-Null
Ok "Aturan firewall: $ruleName (profil Private/Domain)."

# ----------------------------------------------------------------- verifikasi
Info "Menunggu server menjawab…"
$ready = $false
foreach ($i in 1..30) {
  try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/__ahass/api/health" -UseBasicParsing -TimeoutSec 2
    if ($r.StatusCode -eq 200) { $ready = $true; break }
  } catch { Start-Sleep -Seconds 1 }
}
if (-not $ready) {
  Die "Server belum menjawab. Cek log: Get-Content '$DataDir\logs\panel.log' -Tail 40"
}
Ok "Server panel menjawab di port $Port."

# -------------------------------------------------------------------- ringkasan
$ips = Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } |
  Select-Object -ExpandProperty IPAddress
if (-not $ips) { $ips = @("IP-PC") }

$passFile = Join-Path $DataDir "ADMIN-PASSWORD.txt"
Write-Host ""
Write-Host "─────────────────────────────────────────────────────────────"
Ok "Server PC (Windows) siap dipakai STB."
foreach ($ip in $ips) { Write-Host "  Alamat LAN : http://${ip}:$Port/" }
Write-Host "  Admin      : http://IP-PC:$Port/admin"
if (Test-Path $passFile) { Write-Host "  Password   : $(Get-Content $passFile -TotalCount 1)" }
Write-Host ""
Write-Host "  Cek jalur  : node `"$AppDir\pc\doctor.js`" --port=$Port"
Write-Host "  Pasang STB : (di STB) sudo bash pc/client/install.sh --pc=IP-PC"
Write-Host "  Log        : $DataDir\logs\panel.log"
Write-Host "─────────────────────────────────────────────────────────────"
