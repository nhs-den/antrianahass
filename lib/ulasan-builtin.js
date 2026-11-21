'use strict';

/**
 * Widget ulasan Google "bawaan" - dijalankan panel sendiri.
 *
 * Panel membuka port 3000 dan menyajikan dua hal:
 *   /loader.js      -> skrip kecil yang menggambar ulasan di kotak ke-3
 *                      (kompatibel dengan snippet ulasan-google: ?kiosk=1)
 *   /reviews.json   -> data ulasan yang dipakai /loader.js dan mode bawaan panel
 *
 * Sumber datanya salah satu:
 *   a) URL JSON ulasan  (admin -> Ulasan Google -> URL JSON ulasan), atau
 *   b) Google Places API (API key + Place ID) lewat lib/reviews.js.
 *
 * Dengan begitu widget ulasan menyala otomatis bersama panel tanpa perlu
 * memasang aplikasi ulasan-google terpisah. Bila aplikasi terpisah memang ada
 * (di folder yang diisi admin), proses itu yang dipakai dan port ini dibiarkan.
 */

const http = require('http');
const reviews = require('./reviews');
const util = require('./util');

const DEFAULT_PORT = 3000;

function escapeHtml(text) {
  return String(text == null ? '' : text)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

/** Skrip loader yang dipasang di kotak ke-3 panel. */
function loaderScript(port) {
  return `(function () {
  var host = document.currentScript && document.currentScript.parentNode;
  if (!host) return;
  var PORT = ${Number(port) || DEFAULT_PORT};
  var box = document.createElement('div');
  box.style.cssText = 'height:100%;width:100%;display:flex;flex-direction:column;justify-content:center;gap:6px;font:12px/1.45 system-ui,"DejaVu Sans",sans-serif;color:inherit;overflow:hidden';
  host.innerHTML = '';
  host.appendChild(box);

  function stars(n) {
    var full = Math.max(0, Math.min(5, Math.round(n || 0)));
    var out = '';
    for (var i = 0; i < 5; i += 1) out += i < full ? '\\u2605' : '\\u2606';
    return out;
  }
  function paint(data) {
    var items = (data && data.items) || [];
    if (!items.length) {
      box.innerHTML = '<div style="opacity:.6;font-size:11px">Belum ada ulasan.</div>';
      return;
    }
    var i = 0;
    function one() {
      var r = items[i % items.length];
      var html = '';
      if (data.rating) {
        html += '<div style="color:#fbbf24;font-size:11px">' + stars(r.rating || data.rating) +
          ' <span style="color:inherit;opacity:.65">' + (data.rating || '') + '/5' +
          (data.total ? ' \\u00b7 ' + data.total + ' ulasan' : '') + '</span></div>';
      } else {
        html += '<div style="color:#fbbf24;font-size:11px">' + stars(r.rating) + '</div>';
      }
      html += '<div style="line-height:1.4">\\u201c' + (r.text || '') + '\\u201d</div>';
      html += '<div style="opacity:.65;font-size:10px">\\u2014 ' + (r.author || 'Pelanggan') +
        (r.time ? ' \\u00b7 ' + r.time : '') + '</div>';
      box.innerHTML = html;
      i += 1;
    }
    one();
    setInterval(one, 10000);
  }
  function load() {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', 'http://' + (location.hostname || '127.0.0.1') + ':' + PORT + '/reviews.json?t=' + (new Date).getTime(), true);
    xhr.onload = function () {
      try { paint(JSON.parse(xhr.responseText)); } catch (e) { setTimeout(load, 5000); }
    };
    xhr.onerror = function () {
      box.innerHTML = '<div style="opacity:.6;font-size:11px">Ulasan belum termuat\\u2026</div>';
      setTimeout(load, 5000);
    };
    xhr.send();
  }
  load();
}());`;
}

/* ------------------------------------------------------------------ */

let server = null;
let state = {
  active: false,
  port: /** @type {number|null} */ (null),
  error: '',
  startedAt: 0
};
/** @type {(cfg:object)=>object} */
let getConfig = () => ({ reviews: {} });

async function handle(req, res) {
  const url = new URL(req.url, 'http://127.0.0.1');
  const cfg = getConfig();

  if (url.pathname === '/loader.js') {
    const body = Buffer.from(loaderScript(state.port));
    res.writeHead(200, {
      'content-type': 'application/javascript; charset=utf-8',
      'content-length': body.length,
      'cache-control': 'no-store',
      'access-control-allow-origin': '*'
    });
    res.end(body);
    return;
  }

  if (url.pathname === '/reviews.json' || url.pathname === '/api/reviews') {
    try {
      const data = await fetchData(cfg, url.searchParams.get('force') === '1');
      const body = Buffer.from(JSON.stringify(data));
      res.writeHead(200, {
        'content-type': 'application/json; charset=utf-8',
        'content-length': body.length,
        'cache-control': 'no-store',
        'access-control-allow-origin': '*'
      });
      res.end(body);
    } catch (err) {
      util.sendJson(res, 200, { ok: false, error: err.message, items: [], rating: 0, total: 0 });
    }
    return;
  }

  if (url.pathname === '/' || url.pathname === '/index.html') {
    const html = '<!doctype html><meta charset="utf-8"><title>Ulasan Google (bawaan)</title>' +
      '<body style="margin:0;background:#0b1017;color:#e9f1f9;font:14px system-ui;padding:12px">' +
      '<p>Widget ulasan bawaan panel AHASS. Loader: <code>/loader.js?kiosk=1</code></p>' +
      '<div id="w"></div><script async src="/loader.js?kiosk=1"></script></body>';
    const body = Buffer.from(html);
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'content-length': body.length });
    res.end(body);
    return;
  }

  util.sendError(res, 404, 'Tidak ditemukan');
}

/**
 * Ambil data ulasan: dari URL JSON (bila diisi) atau dari Google Places API.
 * Dipakai /reviews.json milik widget bawaan.
 */
async function fetchData(cfg, force) {
  const r = (cfg && cfg.reviews) || {};
  const jsonUrl = String(r.jsonUrl || '').trim();

  if (jsonUrl && r.mode !== 'places') {
    // JSON dari URL apa pun diseragamkan supaya loader.js bisa membacanya.
    const raw = await fetchJsonUrl(jsonUrl);
    return reviews.normalizePayload(raw, Number(r.maxReviews) || 10);
  }
  // PENTING: jangan memanggil reviews.get() untuk mode script dari sini —
  // reviews.get() justru memanggil widget bawaan, sehingga terjadi rekursi
  // (permintaan HTTP ke diri sendiri) tanpa henti.
  if (r.mode === 'places' || r.mode === 'ulasan') {
    return reviews.get(cfg, force);
  }
  const err = new Error(
    'URL JSON ulasan belum diisi. Isi di admin → Ulasan Google → ' +
    '"URL JSON ulasan", atau pilih Google Places API (API key + Place ID).'
  );
  err.code = 'REVIEWS_EMPTY_SOURCE';
  throw err;
}

async function fetchJsonUrl(target) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10000);
  try {
    const res = await fetch(target, {
      signal: controller.signal,
      headers: { accept: 'application/json', 'user-agent': 'ahass-panel-builtin/1.0' }
    });
    const text = await res.text();
    if (!res.ok) throw new Error('HTTP ' + res.status);
    return JSON.parse(text);
  } finally {
    clearTimeout(timer);
  }
}

/** Apakah sumber ulasan sudah cukup untuk menampilkan sesuatu? */
function hasSource(cfg) {
  const r = (cfg && cfg.reviews) || {};
  const s = r.script || {};
  if (s.dir) return false;                    // aplikasi terpisah yang dipakai
  if (!r.mode || r.mode === 'off' || r.mode === 'embed') return false;
  if (r.mode === 'places') return Boolean(r.apiKey && r.placeId);
  if (r.mode === 'ulasan') return Boolean(r.ulasanUrl);
  // mode script: widget bawaan selalu bisa dipakai; isi URL JSON untuk data nyata
  return true;
}

function start(cfgFn) {
  if (typeof cfgFn === 'function') getConfig = cfgFn;
  const cfg = getConfig();
  const r = cfg.reviews || {};
  const s = r.script || {};
  if (!hasSource(cfg)) {
    return { ok: false, message: 'Sumber ulasan belum diisi (URL JSON atau Place ID + API key).' };
  }

  const port = Number(s.port) || DEFAULT_PORT;

  if (server) {
    if (state.port === port) return { ok: true, message: 'Widget bawaan sudah berjalan di port ' + port + '.', port };
    stop();
  }

  server = http.createServer((req, res) => {
    handle(req, res).catch((err) => {
      try { util.sendError(res, 500, err.message); } catch (_e) { /* diabaikan */ }
    });
  });
  server.on('error', (err) => {
    state.active = false;
    state.error = err.code === 'EADDRINUSE'
      ? 'port ' + port + ' sudah dipakai (mungkin aplikasi ulasan-google terpisah)'
      : err.message;
    util.log('Ulasan bawaan: ' + state.error);
    server = null;
  });
  server.listen(port, '0.0.0.0', () => {
    state = { active: true, port, error: '', startedAt: Date.now() };
    util.log('Ulasan bawaan: /loader.js + /reviews.json siap di port ' + port);
  });

  return { ok: true, message: 'Widget ulasan bawaan dijalankan di port ' + port + '.', port };
}

function stop() {
  if (!server) return { ok: true };
  try { server.close(); } catch (_e) { /* diabaikan */ }
  server = null;
  state = { active: false, port: null, error: '', startedAt: 0 };
  return { ok: true };
}

function status() {
  return {
    active: state.active,
    port: state.port,
    error: state.error,
    since: state.startedAt ? Math.round((Date.now() - state.startedAt) / 1000) : null
  };
}

module.exports = { start, stop, status, hasSource, loaderScript, escapeHtml, fetchJsonUrl };
