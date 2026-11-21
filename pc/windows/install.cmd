@echo off
rem Panel AHASS - pemasang satu-klik untuk Windows 10.
rem
rem   Klik kanan berkas ini > Run as administrator
rem   (atau dari PowerShell: .\pc\windows\install.cmd)
rem
rem Berkas ini hanya membuka PowerShell sebagai Administrator lalu menjalankan
rem install.ps1, sehingga kebijakan eksekusi skrip tidak menjadi masalah.
rem Argumen diteruskan apa adanya, contoh:
rem   install.cmd -Port 9090
rem   install.cmd -Remove
rem   install.cmd -Purge

setlocal
set "HERE=%~dp0"
set "PS1=%HERE%install.ps1"

if not exist "%PS1%" (
  echo [fail] Tidak menemukan install.ps1 di %HERE%
  pause
  exit /b 1
)

rem Cek hak administrator.
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo [pc] Meminta hak Administrator...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
  exit /b
)

echo.
echo [pc] Menjalankan pemasang Panel AHASS...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*

set "RC=%errorlevel%"
echo.
if not "%RC%"=="0" echo [fail] Pemasang berhenti dengan kode %RC%.
pause
exit /b %RC%
