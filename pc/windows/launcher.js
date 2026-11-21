/*
 * Launcher server Panel AHASS untuk Windows Service.
 *
 * Dipakai oleh service "AhassPanel": binPath = node.exe launcher.js
 *
 * Kenapa launcher, bukan powershell.exe + runner:
 *   - satu proses saja, jadi saat service dihentikan Node ikut mati
 *     (tidak ada proses yatim yang menahan port 8080);
 *   - tidak ada jendela/konsol yang berkedip;
 *   - membaca conf\pc.env sendiri sebelum server.js dimuat.
 *
 * Urutan: baca pc.env -> siapkan folder data -> siapkan log -> muat server.js.
 */
'use strict';

const fs = require('fs');
const path = require('path');

/* ------------------------------------------------------------ lokasi aplikasi
 * Di instalasi Windows berkas ini ada di  <app>\windows\launcher.js
 * (app root = satu tingkat di atas). Saat dijalankan langsung dari dalam repo,
 * satu tingkat di atas adalah  pc\  - maka dicari ke atas sampai ada server.js.
 */
function findAppDir() {
  const starts = [path.resolve(__dirname, '..'), path.resolve(__dirname, '..', '..')];
  for (const dir of starts) {
    try {
      if (fs.existsSync(path.join(dir, 'server.js'))) return dir;
    } catch (_err) { /* lanjut */ }
  }
  return starts[0];
}

const APP_DIR = findAppDir();
const DEFAULT_DATA = process.platform === 'win32'
  ? path.join(process.env.ProgramData || 'C:\\ProgramData', 'antrianahass')
  : '/var/lib/antrianahass';
// Argumen opsional (service tidak memakainya; berguna untuk uji manual):
//   node launcher.js --data=C:\path --port=8080 --host=0.0.0.0
const CLI = {};
for (const arg of process.argv.slice(2)) {
  const m = /^--(data|port|host)=(.+)$/.exec(arg);
  if (m) CLI[m[1]] = m[2];
}
const DATA_DIR = CLI.data || process.env.AHASS_DATA_DIR || DEFAULT_DATA;
const ENV_FILE = path.join(DATA_DIR, 'conf', 'pc.env');
const LOG_DIR = path.join(DATA_DIR, 'logs');
const LOG_FILE = path.join(LOG_DIR, 'panel.log');
const LOG_MAX = 5 * 1024 * 1024;

/* ------------------------------------------------------------- env dari berkas */
function loadEnv(file) {
  let text = '';
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch (_err) {
    return { loaded: false, count: 0 };
  }
  let count = 0;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#') || line.indexOf('=') < 1) continue;
    const i = line.indexOf('=');
    const key = line.slice(0, i).trim();
    let value = line.slice(i + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    // Jangan timpa variabel yang sudah diisi service/system (mis. dari sc config).
    if (!process.env[key]) process.env[key] = value;
    count += 1;
  }
  return { loaded: true, count };
}

for (const dir of [DATA_DIR, LOG_DIR, path.join(DATA_DIR, 'uploads'), path.join(DATA_DIR, 'logos')]) {
  try { fs.mkdirSync(dir, { recursive: true }); } catch (_err) { /* biarkan: error muncul saat tulis */ }
}

const envInfo = loadEnv(ENV_FILE);
if (process.env.AHASS_DATA_DIR && path.resolve(process.env.AHASS_DATA_DIR) !== path.resolve(DATA_DIR)) {
  process.env.AHASS_DATA_DIR = DATA_DIR;  // folder tempat pc.env dibaca yang menang
}
process.env.AHASS_DATA_DIR = DATA_DIR;
if (CLI.port) process.env.PORT = CLI.port;
if (CLI.host) process.env.HOST = CLI.host;
if (!process.env.HOST) process.env.HOST = '0.0.0.0';
if (!process.env.NODE_ENV) process.env.NODE_ENV = 'production';

/* ------------------------------------------------------------------ log berkas */
function rotate() {
  try {
    const st = fs.statSync(LOG_FILE);
    if (st.size > LOG_MAX) {
      try { fs.renameSync(LOG_FILE, LOG_FILE + '.1'); } catch (_e) { /* .1 terkunci: timpa */ }
      try { fs.writeFileSync(LOG_FILE, ''); } catch (_e) { /* abaikan */ }
    }
  } catch (_e) { /* belum ada berkas */ }
}

let logStream = null;
try {
  rotate();
  logStream = fs.createWriteStream(LOG_FILE, { flags: 'a' });
  logStream.on('error', () => { logStream = null; });
} catch (_err) {
  logStream = null;
}

const stamp = () => new Date().toISOString().replace('T', ' ').slice(0, 19);
function write(level, args) {
  const line = `[${stamp()}] ${level} ${args.map((a) => (typeof a === 'string' ? a : safe(a))).join(' ')}`;
  if (logStream) {
    try { logStream.write(line + '\n'); } catch (_e) { /* abaikan */ }
  }
  try { process.stdout.write(line + '\n'); } catch (_e) { /* abaikan */ }
}

function safe(v) {
  if (v instanceof Error) return v.stack || v.message;
  try { return JSON.stringify(v); } catch (_e) { return String(v); }
}

// Tangkap semua keluaran server.js agar masuk ke panel.log.
const origLog = console.log.bind(console);
const origErr = console.error.bind(console);
console.log = (...a) => write('INFO ', a);
console.error = (...a) => write('ERROR', a);
console.warn = (...a) => write('WARN ', a);
process.on('uncaughtException', (err) => {
  write('FATAL', [err]);
  process.exit(1);
});
process.on('unhandledRejection', (err) => {
  write('FATAL', ['unhandledRejection', err]);
});

write('INFO ', [
  `launcher: Node ${process.version} pid ${process.pid}`,
  `app=${APP_DIR}`,
  `data=${DATA_DIR}`,
  envInfo.loaded ? `pc.env=${envInfo.count} variabel` : 'pc.env tidak ditemukan (pakai default)',
  `PORT=${process.env.PORT || '8080'}`,
  `HOST=${process.env.HOST}`
]);

// Sinyal berhenti dari Windows Service: pastikan log ditutup rapi.
for (const sig of ['SIGINT', 'SIGTERM', 'SIGBREAK']) {
  try {
    process.on(sig, () => {
      write('INFO ', [`menerima ${sig}, berhenti`]);
      if (logStream) logStream.end();
      process.exit(0);
    });
  } catch (_e) { /* sinyal tidak didukung */ }
}

try {
  require(path.join(APP_DIR, 'server.js'));
} catch (err) {
  write('FATAL', ['server.js gagal dimuat', err]);
  process.exit(1);
}

void origLog;
void origErr;
