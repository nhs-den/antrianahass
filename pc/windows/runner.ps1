# Runner service Windows untuk Panel AHASS.
#
# Dijalankan oleh Windows Service "AhassPanel" (didaftarkan oleh install-service.ps1).
# Tugasnya: membaca C:\ProgramData\antrianahass\conf\pc.env, lalu menjalankan
# node server.js sebagai proses anak dan menunggu sampai mati. Kalau server mati,
# runner keluar juga supaya Windows Service Recovery menyalakannya lagi.
#
# Butuh: node.exe ada di PATH (atau NODE_EXE diset di pc.env).

$ErrorActionPreference = "Stop"
$DataDir = if ($env:AHASS_DATA_DIR) { $env:AHASS_DATA_DIR } else { "C:\ProgramData\antrianahass" }
$ConfDir = Join-Path $DataDir "conf"
$LogDir = Join-Path $DataDir "logs"
$EnvFile = Join-Path $ConfDir "pc.env"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir "panel.log"

function Write-Log($m) {
  $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m
  Add-Content -Path $Log -Value $line -Encoding UTF8
}

# Batasi ukuran log agar tidak menumpuk (rotasi sederhana 2 MB).
if ((Test-Path $Log) -and ((Get-Item $Log).Length -gt 2MB)) {
  Move-Item -Force $Log "$Log.1"
}

$AppDir = Split-Path -Parent $PSScriptRoot
$NodeExe = "node.exe"
$env:PORT = "8080"

if (Test-Path $EnvFile) {
  foreach ($line in Get-Content $EnvFile) {
    $t = $line.Trim()
    if (-not $t -or $t.StartsWith("#")) { continue }
    $idx = $t.IndexOf("=")
    if ($idx -lt 1) { continue }
    $k = $t.Substring(0, $idx).Trim()
    $v = $t.Substring($idx + 1).Trim()
    if ($k -eq "NODE_EXE") { $NodeExe = $v; continue }
    [Environment]::SetEnvironmentVariable($k, $v, "Process")
  }
} else {
  Write-Log "pc.env tidak ditemukan di $EnvFile - memakai nilai default."
}

$env:AHASS_DATA_DIR = $DataDir
if (-not $env:HOST) { $env:HOST = "0.0.0.0" }

Write-Log "Menjalankan $NodeExe $AppDir\server.js (PORT=$($env:PORT), HOST=$($env:HOST))"
try {
  & $NodeExe (Join-Path $AppDir "server.js") 2>&1 |
    ForEach-Object { "{0} {1}" -f (Get-Date -Format "HH:mm:ss"), $_ } |
    Out-File -Append -FilePath $Log -Encoding UTF8
  Write-Log "Server berhenti dengan kode $LASTEXITCODE."
} catch {
  Write-Log "Gagal menjalankan server: $_"
}
exit 1
