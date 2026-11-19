#!/usr/bin/env node
'use strict';

/**
 * Pemeriksaan cepat kesehatan instalasi panel.
 *   node scripts/doctor.js
 */

const fs = require('fs');
const net = require('net');
const path = require('path');
const { execSync } = require('child_process');

const config = require('../lib/config');
const ddms = require('../lib/ddms');

const lines = [];
const problems = [];

function ok(label, detail) {
  lines.push('  \x1b[32m✓\x1b[0m ' + label + (detail ? ' — ' + detail : ''));
}
function bad(label, detail) {
  lines.push('  \x1b[31m✗\x1b[0m ' + label + (detail ? ' — ' + detail : ''));
  problems.push(label);
}
function warn(label, detail) {
  lines.push('  \x1b[33m!\x1b[0m ' + label + (detail ? ' — ' + detail : ''));
}
function section(title) {
  lines.push('');
  lines.push('\x1b[1m' + title + '\x1b[0m');
}

function checkPort(port) {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.once('error', () => resolve(false));
    server.once('listening', () => server.close(() => resolve(true)));
    server.listen(port, '0.0.0.0');
  });
}

function fileExists(file) {
  try {
    return fs.statSync(file).isFile();
  } catch (_err) {
    return false;
  }
}

function chromiumPath() {
  for (const name of ['chromium', 'chromium-browser', 'google-chrome']) {
    try {
      return execSync('command -v ' + name, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    } catch (_err) { /* lanjut */ }
  }
  return '';
}

(async function main() {
  section('Sistem');
  const major = Number(process.versions.node.split('.')[0]);
  if (major >= 18) ok('Node.js', process.version);
  else bad('Node.js terlalu lama', process.version + ' (butuh >= 18)');
  ok('Platform', process.platform + ' ' + process.arch);

  section('Berkas aplikasi');
  const required = ['server.js', 'lib/proxy.js', 'public/index.html', 'public/admin.html', 'public/assets/logo.png'];
  required.forEach((file) => {
    if (fileExists(path.join(__dirname, '..', file))) ok(file);
    else bad('Hilang: ' + file);
  });

  section('Konfigurasi');
  try {
    const cfg = config.get();
    ok('config.json', config.CONFIG_PATH);
    ok('Data dir', config.DATA_DIR);
    const passwordFile = path.join(config.DATA_DIR, 'ADMIN-PASSWORD.txt');
    if (fileExists(passwordFile)) warn('File password awal masih ada', passwordFile + ' (boleh dihapus setelah dicatat)');
    if (!cfg.ddms.baseUrl) bad('Alamat DDMS belum diisi');
    else ok('Alamat DDMS', cfg.ddms.baseUrl);
    if (cfg.ddms.autoLogin && !cfg.ddms.username) warn('Login otomatis aktif tetapi username kosong');
    if (cfg.ddms.autoLogin && !config.ddmsPassword()) warn('Login otomatis aktif tetapi password DDMS kosong');
    ok('Mode ulasan', cfg.reviews.mode);
    ok('Kotak 4 (gambar)', String((cfg.gallery.images || []).length) + ' item');
    ok('Kotak 5 (video)', String((cfg.gallery.videos || []).length) + ' item');

    const testFile = path.join(config.DATA_DIR, '.write-test');
    try {
      fs.writeFileSync(testFile, 'ok');
      fs.unlinkSync(testFile);
      ok('Data dir dapat ditulis');
    } catch (err) {
      bad('Data dir tidak dapat ditulis', err.message);
    }

    section('Koneksi DDMS');
    const ping = await ddms.ping();
    if (ping.ok) ok('Terhubung', 'HTTP ' + ping.status + ' dalam ' + ping.ms + ' ms');
    else warn('Tidak dapat dihubungi', ping.error || ('HTTP ' + ping.status));

    section('Koneksi ulasan Google');
    if (cfg.reviews.mode === 'off') {
      warn('Widget ulasan dinonaktifkan');
    } else if (cfg.reviews.mode === 'embed') {
      ok('Mode embed', cfg.reviews.embedUrl || '(URL kosong)');
    } else {
      const reviews = require('../lib/reviews');
      try {
        const data = await reviews.get(cfg, true);
        ok('Ulasan diterima', (data.items || []).length + ' ulasan, rating ' + (data.rating || '-'));
      } catch (err) {
        bad('Gagal memuat ulasan', err.message);
      }
    }
  } catch (err) {
    bad('Gagal membaca konfigurasi', err.message);
  }

  section('Layanan');
  const port = Number(process.env.PORT || 8080);
  const free = await checkPort(port);
  if (free) warn('Port ' + port + ' bebas (server panel sepertinya tidak berjalan)');
  else ok('Port ' + port + ' dipakai (server panel berjalan)');

  const chrome = chromiumPath();
  if (chrome) ok('Chromium', chrome);
  else bad('Chromium tidak ditemukan', 'apt-get install -y chromium');

  try {
    const active = execSync('systemctl is-active ahass-panel.service', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    if (active === 'active') ok('ahass-panel.service', 'aktif');
    else warn('ahass-panel.service', active);
  } catch (_err) {
    warn('ahass-panel.service', 'tidak terpasang (menjalankan dari folder proyek?)');
  }

  console.log(lines.join('\n'));
  console.log('');
  if (problems.length) {
    console.log('\x1b[31m' + problems.length + ' masalah ditemukan.\x1b[0m');
    process.exitCode = 1;
  } else {
    console.log('\x1b[32mSemua pemeriksaan penting lolos.\x1b[0m');
  }
})();
