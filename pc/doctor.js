#!/usr/bin/env node
/*
 * Cek cepat jalur PC ↔ STB tanpa mengubah apa pun.
 *
 *   node pc/doctor.js                       # cek lokal (server + jaringan)
 *   node pc/doctor.js --url=http://192.168.1.10:8080/
 *   node pc/doctor.js --port=8080
 *
 * Yang diperiksa: server menjawab, alamat IP yang harus dipakai STB, port
 * terbuka untuk alamat non-loopback, dan (bila diberi --url) STB/client bisa
 * menjangkau panel dari sudut pandang jaringan.
 *
 * Tanpa dependensi; cukup Node 18+.
 */
'use strict';

const os = require('os');
const http = require('http');
const net = require('net');

const args = { port: 8080, url: '' };
for (const a of process.argv.slice(2)) {
  if (a.startsWith('--port=')) args.port = Number(a.slice(7)) || 8080;
  else if (a.startsWith('--url=')) args.url = a.slice(6);
  else if (a === '-h' || a === '--help') {
    console.log('Pakai: node pc/doctor.js [--port=8080] [--url=http://IP-PC:8080/]');
    process.exit(0);
  }
}

const C = { ok: '\x1b[32m', warn: '\x1b[33m', err: '\x1b[31m', info: '\x1b[36m', rs: '\x1b[0m' };
let fails = 0;
const ok = (l, d = '') => console.log(`${C.ok}[ ok ]${C.rs} ${l.padEnd(30)} ${d}`);
const warn = (l, d = '') => console.log(`${C.warn}[warn]${C.rs} ${l.padEnd(30)} ${d}`);
const bad = (l, d = '') => { fails += 1; console.log(`${C.err}[fail]${C.rs} ${l.padEnd(30)} ${d}`); };
const info = (m) => console.log(`${C.info}[pc]${C.rs} ${m}`);

function get(host, port, path, timeout = 3000) {
  return new Promise((resolve) => {
    const req = http.get({ host, port, path, timeout, headers: { 'user-agent': 'ahass-doctor' } }, (res) => {
      let body = '';
      res.on('data', (c) => { body += c; if (body.length > 4096) req.destroy(); });
      res.on('end', () => resolve({ status: res.statusCode, body }));
    });
    req.on('timeout', () => { req.destroy(); resolve({ status: 0, body: '' }); });
    req.on('error', () => resolve({ status: 0, body: '' }));
  });
}

function tcp(host, port, timeout = 1500) {
  return new Promise((resolve) => {
    const s = net.connect({ host, port });
    const done = (v) => { s.destroy(); resolve(v); };
    s.setTimeout(timeout, () => done(false));
    s.on('connect', () => done(true));
    s.on('error', () => done(false));
  });
}

(async () => {
  console.log('Panel AHASS - diagnosa PC (server)');
  console.log('─────────────────────────────────────────────────────────────');

  const addr = Object.values(os.networkInterfaces()).flat()
    .filter((i) => i && i.family === 'IPv4' && !i.internal)
    .map((i) => i.address);

  if (addr.length) ok('alamat LAN PC', addr.join(', '));
  else bad('alamat LAN PC', 'tidak ada antarmuka IPv4 non-loopback (PC offline?)');
  addr.forEach((ip) => info(`pakai di STB: http://${ip}:${args.port}/`));

  const local = await get('127.0.0.1', args.port, '/__ahass/api/health');
  if (local.status === 200) {
    let h = {};
    try { h = JSON.parse(local.body); } catch { /* biarkan */ }
    const d = h.ddms || {};
    const ddmsState = d.lastOkAt ? 'terhubung' : (d.lastStatus ? `HTTP ${d.lastStatus}` : 'belum dipanggil');
    ok('server panel (loopback)', `v${h.version || '?'} · ${h.memoryMB || '?'} MB · DDMS ${ddmsState}`);
  } else {
    bad('server panel (loopback)', `port ${args.port} tidak menjawab`);
    info('jalankan: sudo systemctl start ahass-panel  |  atau  node server.js');
  }

  if (addr.length) {
    const viaLan = await get(addr[0], args.port, '/__ahass/api/health');
    if (viaLan.status === 200) {
      ok('server dari alamat LAN', `${addr[0]}:${args.port} menjawab`);
    } else {
      bad('server dari alamat LAN', `${addr[0]}:${args.port} tidak menjawab`);
      info('server harus HOST=0.0.0.0 (default). Cek unit: systemctl cat ahass-panel | grep HOST');
    }
  }

  const openPort = await tcp('127.0.0.1', args.port);
  if (openPort) ok('port terbuka', String(args.port));
  else warn('port terbuka', `tidak ada yang listen di ${args.port}`);

  if (args.url) {
    const u = new URL(args.url);
    const r = await get(u.hostname, Number(u.port) || 80, '/__ahass/api/health');
    if (r.status === 200) ok('URL target (STB)', `${args.url} → ${r.status}`);
    else bad('URL target (STB)', `${args.url} tidak menjawab (${r.status || 'timeout'})`);
  }

  console.log('─────────────────────────────────────────────────────────────');
  if (fails === 0) {
    console.log(`${C.ok}Jalur PC siap. Di STB cukup arahkan ke http://IP-PC:${args.port}/${C.rs}`);
    console.log('Kalau STB masih kosong, cek dari STB:  curl -s http://IP-PC:' + args.port + '/__ahass/api/health');
    process.exit(0);
  }
  console.log(`${C.err}${fails} pemeriksaan gagal.${C.rs}`);
  process.exit(1);
})();
