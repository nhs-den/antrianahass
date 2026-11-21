'use strict';

/**
 * AHASS Munjul Motor - Panel Display Kiosk
 * Server tanpa dependensi (Node >= 18). Ringan untuk Intel Compute Stick.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

const config = require('./lib/config');
const util = require('./lib/util');
const auth = require('./lib/auth');
const reviews = require('./lib/reviews');
const statics = require('./lib/static');
const ddms = require('./lib/ddms');
const proxy = require('./lib/proxy');
const ulasanPage = require('./lib/ulasan-page');
const screen = require('./lib/screen');

const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';
const STARTED_AT = Date.now();

/* ------------------------------------------------------------------ *
 * Server-Sent Events - panel ikut berubah tanpa reload
 * ------------------------------------------------------------------ */

const sseClients = new Set();

function broadcast(event) {
  const payload = 'data: ' + JSON.stringify(event) + '\n\n';
  for (const res of sseClients) {
    try {
      res.write(payload);
    } catch (_err) {
      sseClients.delete(res);
    }
  }
}

setInterval(() => {
  for (const res of sseClients) {
    try {
      res.write(': ping\n\n');
    } catch (_err) {
      sseClients.delete(res);
    }
  }
}, 25000).unref();

/* ------------------------------------------------------------------ *
 * Sanitasi input admin
 * ------------------------------------------------------------------ */

function clampInt(value, min, max, fallback) {
  const n = Math.round(Number(value));
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

function cleanText(value, max) {
  return String(value == null ? '' : value).trim().slice(0, max || 200);
}

function sanitizeGallery(list, max) {
  if (!Array.isArray(list)) return [];
  const out = [];
  for (let i = 0; i < list.length && out.length < (max || 30); i += 1) {
    const item = list[i] || {};
    const url = util.sanitizeUrl(item.url);
    if (!url) continue;
    out.push({
      id: cleanText(item.id, 40) || 'i' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
      url: url,
      caption: cleanText(item.caption, 160)
    });
  }
  return out;
}

function buildPatch(body) {
  const patch = {};
  const src = body || {};

  if (src.display) {
    const d = src.display;
    patch.display = {
      leftPercent: clampInt(d.leftPercent, 20, 60, 30),
      scalePercent: clampInt(d.scalePercent, 50, 100, 100),
      offsetX: clampInt(d.offsetX, -200, 200, 0),
      offsetY: clampInt(d.offsetY, -200, 200, 0),
      clock24: d.clock24 !== false,
      showSeconds: d.showSeconds !== false,
      theme: d.theme === 'light' ? 'light' : 'dark',
      rotateSeconds: clampInt(d.rotateSeconds, 4, 120, 12),
      videoSeconds: clampInt(d.videoSeconds, 5, 300, 30),
      intervalSeconds: clampInt(d.intervalSeconds, 5, 600, 20),
      cursorHidden: d.cursorHidden !== false
    };
  }

  if (src.logo) {
    patch.logo = {
      url: util.sanitizeUrl(src.logo.url) || '/assets/logo.png',
      title: cleanText(src.logo.title, 80),
      subtitle: cleanText(src.logo.subtitle, 60),
      tagline: cleanText(src.logo.tagline, 90)
    };
  }

  if (src.ddms) {
    const d = src.ddms;
    const baseUrl = util.sanitizeUrl(d.baseUrl, { stripOrigin: true });
    patch.ddms = {
      enabled: d.enabled !== false,
      baseUrl: baseUrl || config.get().ddms.baseUrl,
      path: (cleanText(d.path, 120) || '/ddms').replace(/\/+$/, '') || '',
      autoLogin: d.autoLogin !== false,
      username: cleanText(d.username, 120),
      userSelector: cleanText(d.userSelector, 160),
      passSelector: cleanText(d.passSelector, 160),
      submitSelector: cleanText(d.submitSelector, 160),
      reloadMinutes: clampInt(d.reloadMinutes, 0, 1440, 0),
      allowInsecureTls: !!d.allowInsecureTls
    };
    if (typeof d.password === 'string' && d.password.length) {
      patch.ddms.password = util.encrypt(d.password, config.SECRET_PATH);
    }
    if (d.clearPassword) patch.ddms.password = '';
  }

  if (src.reviews) {
    const r = src.reviews;
    const mode = ['off', 'script', 'places', 'ulasan', 'embed'].indexOf(r.mode) !== -1 ? r.mode : 'off';
    patch.reviews = {
      mode: mode,
      placeId: cleanText(r.placeId, 300),
      language: cleanText(r.language, 12) || 'id',
      ulasanUrl: util.sanitizeUrl(r.ulasanUrl),
      embedUrl: util.sanitizeUrl(r.embedUrl),
      maxReviews: clampInt(r.maxReviews, 1, 20, 10),
      cacheMinutes: clampInt(r.cacheMinutes, 2, 1440, 60),
      showAvatar: r.showAvatar !== false,
      refreshMinutes: clampInt(r.refreshMinutes, 0, 1440, 30),
      script: {
        // snippet disimpan apa adanya (maks 8 KB), sisanya parameter pembangkit URL
        code: String((r.script && r.script.code) || '').trim().slice(0, 8192),
        host: cleanText(r.script && r.script.host, 120).replace(/^https?:\/\//i, '').replace(/\/+$/, ''),
        port: clampInt(r.script && r.script.port, 1, 65535, 3000),
        path: cleanText(r.script && r.script.path, 200) || '/loader.js',
        query: cleanText(r.script && r.script.query, 200)
      }
    };
    if (typeof r.apiKey === 'string' && r.apiKey.length) {
      patch.reviews.apiKey = cleanText(r.apiKey, 200);
    }
    if (r.clearApiKey) patch.reviews.apiKey = '';
  }

  if (src.gallery) {
    patch.gallery = {
      images: sanitizeGallery(src.gallery.images, 20),
      videos: sanitizeGallery(src.gallery.videos, 20)
    };
  }

  return patch;
}

/* ------------------------------------------------------------------ *
 * API
 * ------------------------------------------------------------------ */

async function handleApi(req, res, url) {
  const p = url.pathname;
  const method = req.method || 'GET';
  const cfg = config.get();

  /* ---------------- endpoint publik (dipakai panel) ---------------- */

  if (p === '/__ahass/api/config' && method === 'GET') {
    util.sendJson(res, 200, config.publicConfig());
    return;
  }

  if (p === '/__ahass/api/reviews' && method === 'GET') {
    try {
      const force = url.searchParams.get('force') === '1';
      const data = await reviews.get(cfg, force);
      util.sendJson(res, 200, Object.assign({ ok: true }, data));
    } catch (err) {
      util.sendJson(res, 200, { ok: false, error: err.message || 'Gagal memuat ulasan' });
    }
    return;
  }

  if (p === '/__ahass/api/health' && method === 'GET') {
    util.sendJson(res, 200, {
      ok: true,
      version: config.VERSION,
      uptimeSeconds: Math.round((Date.now() - STARTED_AT) / 1000),
      memoryMB: Math.round(process.memoryUsage().rss / 1048576),
      ddms: proxy.proxyStatus(),
      authed: auth.isAuthed(req)
    });
    return;
  }

  if (p === '/__ahass/api/events' && method === 'GET') {
    res.writeHead(200, {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-store',
      connection: 'keep-alive',
      'x-accel-buffering': 'no'
    });
    res.write('retry: 5000\n\n');
    res.write('data: ' + JSON.stringify({ type: 'hello', at: Date.now() }) + '\n\n');
    sseClients.add(res);
    req.on('close', () => sseClients.delete(res));
    return;
  }

  // kredensial login otomatis, hanya untuk token yang baru dibuat proxy
  if (p === '/__ahass/api/autologin' && method === 'GET') {
    const token = url.searchParams.get('t') || '';
    if (!proxy.consumeLoginToken(token)) {
      util.sendError(res, 403, 'Token tidak valid atau kedaluwarsa');
      return;
    }
    const creds = config.ddmsCredentials();
    util.sendJson(res, 200, {
      ok: true,
      username: creds.username,
      password: creds.password,
      userSelector: creds.userSelector,
      passSelector: creds.passSelector,
      submitSelector: creds.submitSelector
    });
    return;
  }

  /* ---------------- admin ---------------- */

  if (p === '/__ahass/api/admin/session' && method === 'GET') {
    util.sendJson(res, 200, { ok: true, authed: auth.isAuthed(req), version: config.VERSION });
    return;
  }

  if (p === '/__ahass/api/admin/login' && method === 'POST') {
    const body = await util.readJson(req, 8192);
    auth.login(req, res, String(body.password || ''));
    return;
  }

  if (p === '/__ahass/api/admin/logout' && method === 'POST') {
    auth.destroySession(req, res);
    util.sendJson(res, 200, { ok: true });
    return;
  }

  // semua endpoint di bawah butuh login
  if (!auth.requireAuth(req, res)) return;

  if (p === '/__ahass/api/admin/config' && method === 'GET') {
    util.sendJson(res, 200, Object.assign({ ok: true }, config.adminConfig()));
    return;
  }

  if (p === '/__ahass/api/admin/config' && (method === 'PUT' || method === 'POST')) {
    const body = await util.readJson(req, 512 * 1024);
    const patch = buildPatch(body);
    const updated = config.update(patch);
    reviews.clearCache();
    broadcast({ type: 'config', at: Date.now() });
    util.sendJson(res, 200, { ok: true, updatedAt: updated.updatedAt, config: config.adminConfig() });
    return;
  }

  if (p === '/__ahass/api/admin/logo' && method === 'POST') {
    const body = await util.readJson(req, 8 * 1024 * 1024);
    let savedUrl = '';

    if (body.dataUrl) {
      const match = /^data:(image\/(png|jpeg|jpg|webp|gif|svg\+xml));base64,(.+)$/i.exec(String(body.dataUrl));
      if (!match) {
        util.sendError(res, 400, 'Format gambar tidak dikenali. Gunakan PNG, JPG, WEBP, atau SVG.');
        return;
      }
      const mime = match[1].toLowerCase();
      const ext = mime.indexOf('svg') !== -1 ? 'svg' : mime.indexOf('jpeg') !== -1 || mime.indexOf('jpg') !== -1 ? 'jpg' : mime.split('/')[1];
      const buffer = Buffer.from(match[3], 'base64');
      if (buffer.length > 5 * 1024 * 1024) {
        util.sendError(res, 413, 'Ukuran gambar maksimal 5 MB.');
        return;
      }
      config.ensureDirs();
      const name = 'logo-' + Date.now().toString(36) + '.' + ext;
      fs.writeFileSync(path.join(config.UPLOAD_DIR, name), buffer);
      // hapus logo unggahan lama
      for (const file of fs.readdirSync(config.UPLOAD_DIR)) {
        if (/^logo-/.test(file) && file !== name) {
          try { fs.unlinkSync(path.join(config.UPLOAD_DIR, file)); } catch (_e) { /* diabaikan */ }
        }
      }
      savedUrl = '/__ahass/uploads/' + name;
    } else if (body.url) {
      const cleaned = util.sanitizeUrl(body.url);
      if (!cleaned) {
        util.sendError(res, 400, 'URL logo tidak valid.');
        return;
      }
      savedUrl = cleaned;
    } else if (body.reset) {
      savedUrl = '/assets/logo.png';
    } else {
      util.sendError(res, 400, 'Tidak ada gambar yang dikirim.');
      return;
    }

    config.update({ logo: { url: savedUrl } });
    broadcast({ type: 'config', at: Date.now() });
    util.sendJson(res, 200, { ok: true, url: savedUrl });
    return;
  }

  if (p === '/__ahass/api/admin/password' && method === 'POST') {
    const body = await util.readJson(req, 4096);
    const current = String(body.current || '');
    const next = String(body.next || '');
    if (next.length < 6) {
      util.sendError(res, 400, 'Password baru minimal 6 karakter.');
      return;
    }
    if (!config.verifyPassword(current, cfg.admin.passwordHash, cfg.admin.passwordSalt)) {
      util.sendError(res, 401, 'Password saat ini salah.');
      return;
    }
    config.setAdminPassword(cfg, next);
    config.save();
    util.sendJson(res, 200, { ok: true, message: 'Password admin berhasil diubah.' });
    return;
  }

  if (p === '/__ahass/api/admin/reviews/test' && method === 'POST') {
    try {
      const data = await reviews.get(config.get(), true);
      util.sendJson(res, 200, { ok: true, data: data });
    } catch (err) {
      util.sendJson(res, 200, { ok: false, error: err.message });
    }
    return;
  }

  if (p === '/__ahass/api/admin/reviews/clear-cache' && method === 'POST') {
    reviews.clearCache();
    util.sendJson(res, 200, { ok: true });
    return;
  }

  if (p === '/__ahass/api/admin/system/screen' && method === 'GET') {
    try {
      util.sendJson(res, 200, Object.assign({ ok: true }, screen.info()));
    } catch (err) {
      util.sendJson(res, 200, { ok: false, supported: false, error: err.message });
    }
    return;
  }

  if (p === '/__ahass/api/admin/system/resolution' && method === 'POST') {
    const body = await util.readJson(req, 8 * 1024);
    const width = Number(body && body.width) || 0;
    const height = Number(body && body.height) || 0;
    const overscan = !!(body && body.overscan);

    if (!width && !height && !overscan) {
      util.sendJson(res, 400, { ok: false, error: 'Pilih resolusi atau centang matikan overscan.' });
      return;
    }

    try {
      const result = screen.apply({ width, height, overscan });
      // Jawab dulu, reboot menyusul: kalau reboot dipicu sebelum respons
      // terkirim, browser admin akan melihat "network error" yang
      // membingungkan padahal perubahan sudah tersimpan.
      util.sendJson(res, 200, {
        ok: true,
        changed: result.changes,
        file: result.file,
        message: 'Setelan layar disimpan (' + (result.changes.join(', ') || 'tanpa perubahan') + '). Perangkat akan reboot dalam 2 detik.'
      });
      util.log('Layar: ' + result.changes.join(', ') + ' → reboot');
      setTimeout(() => {
        try {
          require('child_process').spawn('systemctl', ['reboot'], { detached: true, stdio: 'ignore' }).unref();
        } catch (err) {
          util.log('Reboot gagal dijalankan: ' + err.message);
        }
      }, 2000);
    } catch (err) {
      const code = err.code === 'INVALID' ? 400 : 200;
      util.sendJson(res, code, { ok: false, error: err.message, unsupported: err.code === 'UNSUPPORTED' });
    }
    return;
  }

  if (p === '/__ahass/api/admin/ddms/ping' && method === 'POST') {
    util.sendJson(res, 200, Object.assign({ ok: true }, await ddms.ping()));
    return;
  }

  if (p === '/__ahass/api/admin/ddms/test-login' && method === 'POST') {
    try {
      const result = await ddms.testLogin();
      util.sendJson(res, 200, Object.assign({ ok: true, test: result }, { success: result.ok }));
    } catch (err) {
      util.sendJson(res, 200, { ok: false, error: err.message });
    }
    return;
  }

  if (p === '/__ahass/api/admin/status' && method === 'GET') {
    const mem = process.memoryUsage();
    util.sendJson(res, 200, {
      ok: true,
      version: config.VERSION,
      node: process.version,
      platform: os.platform() + ' ' + os.arch(),
      hostname: os.hostname(),
      uptimeSeconds: Math.round((Date.now() - STARTED_AT) / 1000),
      systemUptimeSeconds: Math.round(os.uptime()),
      loadavg: os.loadavg(),
      memory: {
        rssMB: Math.round(mem.rss / 1048576),
        heapMB: Math.round(mem.heapUsed / 1048576),
        freeMB: Math.round(os.freemem() / 1048576),
        totalMB: Math.round(os.totalmem() / 1048576)
      },
      proxy: proxy.proxyStatus(),
      sessions: auth.sessionCount(),
      configPath: config.CONFIG_PATH
    });
    return;
  }

  util.sendError(res, 404, 'Endpoint tidak ditemukan');
}

/* ------------------------------------------------------------------ *
 * Router
 * ------------------------------------------------------------------ */

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://' + (req.headers.host || 'localhost'));
  const p = url.pathname;

  Promise.resolve()
    .then(() => {
      if (p === '/' || p === '/index.html') {
        statics.send(res, 'index.html', { nocache: true });
        return;
      }
      if (p === '/admin' || p === '/admin/' || p === '/admin.html') {
        statics.send(res, 'admin.html', { nocache: true });
        return;
      }
      if (p === '/favicon.ico' || p === '/favicon.svg') {
        statics.send(res, 'assets/favicon.svg', { cache: true });
        return;
      }
      if (p === '/manifest.webmanifest') {
        statics.send(res, 'manifest.webmanifest', { cache: true });
        return;
      }
      if (p.startsWith('/assets/')) {
        // logo bawaan & ikon milik panel (bukan milik DDMS)
        statics.send(res, p.slice(1), { cache: true });
        return;
      }
      if (p === '/__ahass/ulasan' || p === '/__ahass/ulasan/') {
        const html = ulasanPage.render(config.get());
        const body = Buffer.from(html);
        res.writeHead(200, {
          'content-type': 'text/html; charset=utf-8',
          'content-length': body.length,
          'cache-control': 'no-store',
          'x-frame-options': 'SAMEORIGIN'
        });
        res.end(body);
        return;
      }
      if (p.startsWith('/__ahass/static/')) {
        const rel = p.slice('/__ahass/static/'.length);
        statics.send(res, rel, { cache: true });
        return;
      }
      if (p.startsWith('/__ahass/uploads/')) {
        const rel = p.slice('/__ahass/uploads/'.length);
        statics.send(res, rel, { root: config.UPLOAD_DIR, cache: true });
        return;
      }
      if (p.startsWith('/__ahass/')) {
        return handleApi(req, res, url);
      }
      // sisanya milik DDMS
      proxy.proxy(req, res);
      return null;
    })
    .catch((err) => {
      const code = err.status || 500;
      console.error('[ahass] error:', err.message);
      if (!res.headersSent) util.sendError(res, code, err.message || 'Kesalahan server');
      else res.end();
    });
});

proxy.attachUpgrade(server);

server.on('clientError', (err, socket) => {
  if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\n\r\n');
});

/* ------------------------------------------------------------------ *
 * Start
 * ------------------------------------------------------------------ */

config.load();
config.ensureDirs();

server.listen(PORT, HOST, () => {
  util.log('AHASS Panel v' + config.VERSION + ' berjalan di http://' + HOST + ':' + PORT);
  util.log('Panel   : http://localhost:' + PORT + '/');
  util.log('Admin   : http://localhost:' + PORT + '/admin');
  util.log('Data    : ' + config.DATA_DIR);
  const nets = os.networkInterfaces();
  Object.keys(nets).forEach((name) => {
    (nets[name] || []).forEach((net) => {
      if (net.family === 'IPv4' && !net.internal) {
        util.log('Jaringan: http://' + net.address + ':' + PORT + '/');
      }
    });
  });
});

function shutdown(signal) {
  util.log('Menerima ' + signal + ', mematikan server…');
  for (const res of sseClients) {
    try { res.end(); } catch (_e) { /* diabaikan */ }
  }
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 3000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('unhandledRejection', (err) => {
  console.error('[ahass] unhandledRejection:', err && err.message ? err.message : err);
});
