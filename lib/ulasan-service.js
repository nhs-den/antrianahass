'use strict';

/**
 * Pengelola layanan widget ulasan-google (port 3000) supaya bisa hidup
 * berbarengan dengan panel antrian tanpa terminal terpisah.
 *
 * Tiga hal yang dikerjakan modul ini:
 *   1. mencari folder aplikasi ulasan-google di perangkat,
 *   2. menjalankan / menghentikan prosesnya (dipakai saat mode "kelola sendiri"),
 *   3. memasang unit systemd `ulasan-google.service` agar tetap hidup setelah
 *      reboot (sekali klik dari halaman admin).
 *
 * Semua operasi bersifat best-effort: kalau perangkat tidak punya sudo/systemd
 * (mis. mode uji di PC Windows), status akan menjelaskannya, bukan melempar
 * error ke halaman admin.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const { spawn, execFile } = require('child_process');

const UNIT = '/etc/systemd/system/ulasan-google.service';
const SERVICE = 'ulasan-google';

/** Folder yang biasa dipakai (unduhan ZIP, hasil ekstrak, atau ~/ulasan-google). */
function candidateDirs() {
  const home = process.env.HOME || os.homedir() || '/root';
  const list = [];
  for (const dir of [home, '/home', '/root', '/opt', '/srv']) {
    let names = [];
    try {
      names = fs.readdirSync(dir);
    } catch (_err) {
      continue;
    }
    for (const name of names) {
      if (!/ulasan[-_]?google/i.test(name)) continue;
      list.push(path.join(dir, name));
    }
  }
  return list;
}

/** Apakah folder ini kelihatan seperti aplikasi ulasan-google? */
function looksLikeApp(dir) {
  try {
    if (!fs.statSync(dir).isDirectory()) return false;
    for (const f of ['package.json', 'app.py', 'main.py', 'index.php', 'public/index.php', 'start.sh']) {
      if (fs.existsSync(path.join(dir, f))) return true;
    }
  } catch (_err) { /* abaikan */ }
  return false;
}

function findDir(configured) {
  const wanted = String(configured || '').trim();
  if (wanted && looksLikeApp(wanted)) return path.resolve(wanted);
  for (const dir of candidateDirs()) {
    if (looksLikeApp(dir)) return dir;
  }
  return '';
}

/** Perintah untuk menjalankan aplikasi (Node / Python / PHP / start.sh). */
function commandFor(dir) {
  const pkgPath = path.join(dir, 'package.json');
  if (fs.existsSync(pkgPath)) {
    let start = '';
    let main = '';
    try {
      const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
      start = String(pkg.scripts && pkg.scripts.start ? pkg.scripts.start : '');
      main = String(pkg.main || '');
    } catch (_err) { /* abaikan */ }

    const m = start.match(/^node\s+(\S+)/);
    let entry = m ? m[1] : '';
    if (!entry) {
      for (const c of [main, 'server.js', 'app.js', 'index.js', 'main.js', 'src/server.js', 'src/index.js', 'bin/www']) {
        if (c && fs.existsSync(path.join(dir, c))) {
          entry = c;
          break;
        }
      }
    }
    if (entry) return { cmd: process.execPath || 'node', args: [entry] };
    if (start) return { cmd: 'npm', args: ['start'] };
    return null;
  }
  for (const [file, cmd, args] of [
    ['app.py', 'python3', ['app.py']],
    ['main.py', 'python3', ['main.py']],
    ['index.php', 'php', ['-S', '0.0.0.0:PORT', '-t', '.']],
    ['start.sh', 'bash', ['start.sh']]
  ]) {
    if (fs.existsSync(path.join(dir, file))) return { cmd, args };
  }
  return null;
}

/* ------------------------------------------------------------------ *
 * Status
 * ------------------------------------------------------------------ */

let child = null;          // proses yang dijalankan panel (mode kelola sendiri)
let childStartedAt = 0;
let lastError = '';

function run(cmd, args, timeout) {
  return new Promise((resolve) => {
    execFile(cmd, args, { timeout: timeout || 4000 }, (err, stdout, stderr) => {
      resolve({
        ok: !err,
        out: String(stdout || '').trim(),
        err: String(stderr || (err && err.message) || '').trim()
      });
    });
  });
}

/** Cek apakah port menjawab HTTP (loader.js ada atau minimal ada balasan). */
function probe(port) {
  return new Promise((resolve) => {
    const req = http.get({
      host: '127.0.0.1',
      port: port,
      path: '/loader.js',
      timeout: 1500,
      headers: { 'user-agent': 'antrianahass-service-check' }
    }, (res) => {
      res.resume();
      resolve({ up: true, status: res.statusCode || 0 });
    });
    req.on('timeout', () => { req.destroy(); resolve({ up: false, status: 0 }); });
    req.on('error', () => resolve({ up: false, status: 0 }));
  });
}

async function status(cfg) {
  const reviews = (cfg && cfg.reviews) || {};
  const script = reviews.script || {};
  const manage = script.manage !== false;
  const port = Number(script.port) || 3000;
  const dir = findDir(script.dir);

  const systemd = await run('systemctl', ['is-active', SERVICE], 3000);
  const probeResult = await probe(port);

  return {
    manage,
    dir: dir,
    dirFound: Boolean(dir),
    port: port,
    path: script.path || '/loader.js',
    query: script.query || 'kiosk=1',
    running: Boolean(child) || probeResult.up || systemd.out === 'active',
    managedProcess: Boolean(child),
    systemd: {
      installed: fs.existsSync(UNIT),
      active: systemd.out === 'active',
      available: systemd.ok || systemd.out === 'inactive' || systemd.out === 'failed'
    },
    http: probeResult,
    error: lastError,
    since: childStartedAt ? Math.round((Date.now() - childStartedAt) / 1000) : null
  };
}

/* ------------------------------------------------------------------ *
 * Jalankan / hentikan
 * ------------------------------------------------------------------ */

function looksRunning(port) {
  return probe(port).then((r) => r.up);
}

/**
 * Jalankan aplikasi ulasan-google sebagai proses anak panel.
 * @returns {Promise<{ok:boolean, message:string, dir?:string}>}
 */
async function start(cfg) {
  const reviews = (cfg && cfg.reviews) || {};
  const script = reviews.script || {};
  const port = Number(script.port) || 3000;

  if (await looksRunning(port)) {
    lastError = '';
    return { ok: true, message: 'Layanan ulasan sudah berjalan di port ' + port + '.' };
  }

  const dir = findDir(script.dir);
  if (!dir) {
    lastError = 'folder ulasan-google tidak ditemukan';
    return {
      ok: false,
      message: 'Folder aplikasi ulasan-google belum ditemukan. Isi folder di kolom atas, ' +
        'mis. /home/den/ulasan-google-main (hasil ekstrak ZIP).'
    };
  }

  const cmd = commandFor(dir);
  if (!cmd) {
    lastError = 'jenis aplikasi tidak dikenali';
    return { ok: false, message: 'Isi folder ' + dir + ' tidak dikenali (tidak ada package.json/app.py/start.sh).' };
  }
  if (!fs.existsSync(path.join(dir, 'node_modules')) && fs.existsSync(path.join(dir, 'package.json'))) {
    return {
      ok: false,
      message: 'Dependensi belum terpasang. Jalankan sekali: sudo bash deploy/install-ulasan.sh --dir ' + dir
    };
  }

  const args = cmd.args.map((a) => String(a).replace('PORT', String(port)));
  const env = Object.assign({}, process.env, {
    PORT: String(port),
    NODE_ENV: process.env.NODE_ENV || 'production',
    HOST: process.env.HOST || '0.0.0.0'
  });

  try {
    const logFile = path.join(os.tmpdir(), 'ulasan-google.log');
    const out = fs.openSync(logFile, 'a');
    child = spawn(cmd.cmd, args, {
      cwd: dir,
      env: env,
      stdio: ['ignore', out, out],
      detached: false
    });
    childStartedAt = Date.now();
    lastError = '';

    child.on('exit', (code, signal) => {
      child = null;
      childStartedAt = 0;
      if (code !== 0) lastError = 'berhenti (kode ' + code + (signal ? ' / ' + signal : '') + '), log: ' + logFile;
    });
    child.on('error', (err) => {
      child = null;
      childStartedAt = 0;
      lastError = err.message;
    });
  } catch (err) {
    child = null;
    lastError = err.message;
    return { ok: false, message: 'Gagal menjalankan: ' + err.message };
  }

  // Beri waktu singkat supaya kegagalan langsung (port dipakai, modul hilang) terlihat.
  await new Promise((r) => setTimeout(r, 1200));
  const up = await probe(port);
  if (up.up) {
    return { ok: true, message: 'Layanan ulasan dijalankan dari ' + dir + ' (port ' + port + ').', dir: dir };
  }
  return {
    ok: false,
    message: 'Proses dimulai tapi port ' + port + ' belum menjawab.' + (lastError ? ' ' + lastError : '') +
      ' Lihat log: tail -n 20 ' + path.join(os.tmpdir(), 'ulasan-google.log')
  };
}

function stop() {
  if (!child) return { ok: true, message: 'Panel tidak menjalankan proses ulasan (tidak ada yang dihentikan).' };
  try {
    child.kill('SIGTERM');
  } catch (err) {
    return { ok: false, message: 'Gagal menghentikan: ' + err.message };
  }
  child = null;
  childStartedAt = 0;
  return { ok: true, message: 'Layanan ulasan dihentikan.' };
}

/* ------------------------------------------------------------------ *
 * Pasang sebagai layanan sistem (systemd)
 * ------------------------------------------------------------------ */

function isRoot() {
  return typeof process.getuid === 'function' && process.getuid() === 0;
}

/**
 * Tulis /etc/systemd/system/ulasan-google.service lalu aktifkan.
 * Hanya bisa dari panel yang berjalan sebagai root (lihat admin/ulosan docs).
 */
async function install(cfg) {
  if (!isRoot()) {
    return {
      ok: false,
      message: 'Panel berjalan tanpa hak root, jadi unit systemd tidak bisa ditulis. ' +
        'Jalankan sekali di terminal perangkat: sudo bash /opt/antrianahass/deploy/install-ulasan.sh'
    };
  }
  const reviews = (cfg && cfg.reviews) || {};
  const script = reviews.script || {};
  const port = Number(script.port) || 3000;
  const dir = findDir(script.dir);
  if (!dir) return { ok: false, message: 'Folder aplikasi ulasan-google belum ditemukan.' };
  const cmd = commandFor(dir);
  if (!cmd) return { ok: false, message: 'Jenis aplikasi di ' + dir + ' tidak dikenali.' };

  const exec = [cmd.cmd].concat(cmd.args).join(' ');
  const unit = [
    '[Unit]',
    'Description=Service ulasan Google (widget panel AHASS)',
    'After=network-online.target',
    'Wants=network-online.target',
    '',
    '[Service]',
    'Type=simple',
    'WorkingDirectory=' + dir,
    'Environment=NODE_ENV=production',
    'Environment=PORT=' + port,
    'ExecStart=' + exec,
    'Restart=always',
    'RestartSec=5',
    'StandardOutput=journal',
    'StandardError=journal',
    'SyslogIdentifier=ulasan-google',
    '',
    '[Install]',
    'WantedBy=multi-user.target',
    ''
  ].join('\n');

  try {
    fs.writeFileSync(UNIT, unit);
  } catch (err) {
    return { ok: false, message: 'Tidak bisa menulis ' + UNIT + ': ' + err.message };
  }

  stop(); // hindari dua proses di port yang sama
  const reload = await run('systemctl', ['daemon-reload'], 6000);
  const enable = await run('systemctl', ['enable', '--now', SERVICE], 20000);
  if (!enable.ok) {
    return { ok: false, message: 'Unit ditulis tapi gagal diaktifkan: ' + (enable.err || reload.err || 'tidak diketahui') };
  }
  return { ok: true, message: 'ulasan-google.service aktif dan otomatis menyala saat boot (port ' + port + ').' };
}

module.exports = {
  status,
  start,
  stop,
  install,
  findDir,
  commandFor,
  candidateDirs
};
