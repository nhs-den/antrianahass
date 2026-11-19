'use strict';

/**
 * Reverse proxy untuk web DDMS.
 *
 * Kenapa perlu proxy?
 *  - Login otomatis hanya bisa dilakukan bila halaman DDMS berada pada
 *    origin yang sama dengan panel kita (same-origin). Dengan proxy,
 *    iframe DDMS dimuat dari http://localhost:8080/... sehingga skrip
 *    kecil bisa mengisi form login.
 *  - Cookie login otomatis "menempel" di browser kiosk.
 *
 * Yang diteruskan: semua path yang bukan milik panel (/__ahass/*).
 */

const http = require('http');
const https = require('https');
const crypto = require('crypto');
const config = require('./config');

const MAX_HTML_BYTES = 12 * 1024 * 1024;
const UPSTREAM_TIMEOUT_MS = 45000;

const HOP_HEADERS = new Set([
  'connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization',
  'te', 'trailer', 'transfer-encoding', 'upgrade'
]);

// header yang dibuang dari respons upstream
const DROP_RESPONSE_HEADERS = new Set([
  'content-security-policy', 'content-security-policy-report-only',
  'x-frame-options', 'frame-options', 'strict-transport-security',
  'content-encoding', 'content-length', 'etag', 'alt-svc',
  'report-to', 'nel', 'server-timing'
]);

const agents = {
  http: new http.Agent({ keepAlive: true, maxSockets: 24, keepAliveMsecs: 15000 }),
  https: new https.Agent({ keepAlive: true, maxSockets: 24, keepAliveMsecs: 15000, rejectUnauthorized: true }),
  httpsInsecure: new https.Agent({ keepAlive: true, maxSockets: 24, keepAliveMsecs: 15000, rejectUnauthorized: false })
};

/* ------------------------------------------------------------------ *
 * Token sekali pakai untuk kredensial login otomatis
 * ------------------------------------------------------------------ */

const loginTokens = new Map();

function issueLoginToken() {
  const token = crypto.randomBytes(12).toString('base64url');
  loginTokens.set(token, Date.now() + 3 * 60 * 1000);
  if (loginTokens.size > 300) {
    const now = Date.now();
    for (const [k, exp] of loginTokens) if (exp < now) loginTokens.delete(k);
  }
  return token;
}

function consumeLoginToken(token) {
  const exp = loginTokens.get(String(token || ''));
  loginTokens.delete(String(token || ''));
  if (!exp) return false;
  return exp > Date.now();
}

/* ------------------------------------------------------------------ *
 * Status untuk halaman admin / indikator di panel
 * ------------------------------------------------------------------ */

const status = {
  lastOkAt: null,
  lastErrorAt: null,
  lastError: '',
  lastStatus: 0
};

function proxyStatus() {
  return Object.assign({}, status);
}

/* ------------------------------------------------------------------ *
 * Util
 * ------------------------------------------------------------------ */

function upstreamFor(cfg) {
  const raw = (cfg.ddms && cfg.ddms.baseUrl) || '';
  let url;
  try {
    url = new URL(raw);
  } catch (_err) {
    return null;
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
  return url;
}

function rewriteCookies(setCookie) {
  const list = Array.isArray(setCookie) ? setCookie : [setCookie];
  return list
    .filter(Boolean)
    .map((cookie) =>
      String(cookie)
        .split(/;\s*/)
        .filter((part) => {
          if (/^domain=/i.test(part)) return false;   // biar berlaku untuk localhost
          if (/^secure$/i.test(part)) return false;   // kiosk memakai http
          if (/^partitioned$/i.test(part)) return false;
          return true;
        })
        .map((part) => {
          // SameSite=None wajib Secure; karena kiosk memakai http, ubah ke Lax
          if (/^samesite\s*=\s*none$/i.test(part)) return 'SameSite=Lax';
          return part;
        })
        .join('; ')
    );
}

function rewriteLocation(value, base) {
  if (!value) return value;
  const loc = String(value);
  try {
    const abs = new URL(loc, base.origin);
    if (abs.host === base.host) return abs.pathname + abs.search + abs.hash;
  } catch (_err) { /* biarkan */ }
  if (loc.startsWith('//' + base.host)) return loc.slice(('//' + base.host).length) || '/';
  return loc;
}

/** Ubah URL absolut upstream menjadi path relatif agar lewat proxy. */
function rewriteText(text, base) {
  let out = String(text);
  const origins = [base.origin];
  if (base.protocol === 'https:') origins.push('http://' + base.host);
  else origins.push('https://' + base.host);
  for (const origin of origins) {
    out = out.split(origin).join('');
  }
  return out;
}

function injectHtml(html, base, autoLoginEnabled) {
  let out = html.replace(/<meta[^>]+http-equiv=["']?content-security-policy["']?[^>]*>/gi, '');
  const boot =
    '<script>window.__AHASS_PROXY__=' +
    JSON.stringify({ origin: base.origin, host: base.host }).replace(/</g, '\\u003c') +
    ';</script><script src="/__ahass/static/patch.js"></script>';
  if (/<head[^>]*>/i.test(out)) out = out.replace(/<head[^>]*>/i, (m) => m + boot);
  else out = boot + out;

  if (autoLoginEnabled) {
    const token = issueLoginToken();
    const tag = '<script src="/__ahass/static/autologin.js?t=' + token + '" defer></script>';
    if (/<\/body>/i.test(out)) out = out.replace(/<\/body>/i, tag + '</body>');
    else out += tag;
  }
  return out;
}

function collectBody(stream, limit) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    stream.on('data', (c) => {
      size += c.length;
      if (size > limit) {
        const err = new Error('Halaman upstream terlalu besar');
        err.status = 502;
        reject(err);
        stream.destroy();
        return;
      }
      chunks.push(c);
    });
    stream.on('end', () => resolve(Buffer.concat(chunks)));
    stream.on('error', reject);
  });
}

/* ------------------------------------------------------------------ *
 * Halaman galat (bila DDMS tidak bisa dihubungi)
 * ------------------------------------------------------------------ */

function errorPage(res, code, message, base) {
  const safe = String(message || 'Tidak dapat menghubungi server DDMS.')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const html = `<!DOCTYPE html><html lang="id"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>DDMS tidak tersedia</title>
<style>
  html,body{height:100%;margin:0;background:#0b1017;color:#e8eef6;
    font-family:system-ui,-apple-system,"Segoe UI",Roboto,Arial,sans-serif}
  .wrap{height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;padding:24px;text-align:center}
  .dot{width:14px;height:14px;border-radius:50%;background:#f43f5e;box-shadow:0 0 0 6px rgba(244,63,94,.15)}
  h1{font-size:clamp(18px,2.2vw,30px);margin:0;font-weight:650}
  p{margin:0;opacity:.72;font-size:clamp(12px,1.15vw,16px);max-width:52ch;line-height:1.5}
  code{background:#141c26;padding:2px 6px;border-radius:5px;font-size:.92em}
  .count{margin-top:6px;font-size:.92em;opacity:.6}
  a.btn{margin-top:6px;display:inline-block;padding:10px 18px;border-radius:10px;background:#e11d48;color:#fff;text-decoration:none;font-weight:600;font-size:.95em}
</style></head>
<body><div class="wrap">
  <div class="dot"></div>
  <h1>Belum tersambung ke DDMS</h1>
  <p>${safe}</p>
  ${base ? '<p>Target: <code>' + base.origin + '</code></p>' : ''}
  <p class="count">Mencoba ulang otomatis dalam <span id="s">15</span> detik…</p>
  <a class="btn" href="" id="retry">Coba sekarang</a>
</div>
<script>
  try { if (parent !== window) parent.postMessage({ type: 'ahass-ddms-status', ok: false, message: ${JSON.stringify(String(message || ''))} }, '*'); } catch (e) {}
  var n = 15;
  var el = document.getElementById('s');
  var t = setInterval(function(){ n -= 1; if (el) el.textContent = n; if (n <= 0) { clearInterval(t); location.reload(); } }, 1000);
</script>
</body></html>`;
  const body = Buffer.from(html);
  res.writeHead(code, {
    'content-type': 'text/html; charset=utf-8',
    'content-length': body.length,
    'cache-control': 'no-store'
  });
  res.end(body);
}

/* ------------------------------------------------------------------ *
 * Proxy utama
 * ------------------------------------------------------------------ */

function proxy(req, res) {
  const cfg = config.get();
  const base = upstreamFor(cfg);
  if (!base) {
    errorPage(res, 503, 'Alamat web DDMS belum diatur. Buka halaman admin untuk mengisinya.', null);
    return;
  }

  const targetPath = req.url && req.url.startsWith('/') ? req.url : '/' + (req.url || '');
  const isHttps = base.protocol === 'https:';
  const transport = isHttps ? https : http;
  const agent = isHttps
    ? (cfg.ddms.allowInsecureTls ? agents.httpsInsecure : agents.https)
    : agents.http;

  const headers = Object.assign({}, req.headers);
  headers.host = base.host;
  headers['accept-encoding'] = 'identity';
  headers.origin = base.origin;
  if (headers.referer) headers.referer = base.origin + targetPath;
  headers['x-forwarded-host'] = req.headers.host || '';
  headers['x-forwarded-proto'] = 'http';
  delete headers['x-forwarded-for'];

  const options = {
    protocol: base.protocol,
    hostname: base.hostname,
    port: base.port || (isHttps ? 443 : 80),
    path: targetPath,
    method: req.method,
    headers: headers,
    agent: agent,
    servername: isHttps ? base.hostname : undefined
  };

  let finished = false;
  const upstream = transport.request(options, async (upRes) => {
    const ctype = String(upRes.headers['content-type'] || '').toLowerCase();
    const isHtml = ctype.indexOf('text/html') !== -1 || ctype.indexOf('application/xhtml') !== -1;
    const isText =
      isHtml ||
      ctype.indexOf('text/css') !== -1 ||
      ctype.indexOf('javascript') !== -1 ||
      ctype.indexOf('text/plain') !== -1;

    const outHeaders = {};
    Object.keys(upRes.headers).forEach((key) => {
      const lower = key.toLowerCase();
      if (HOP_HEADERS.has(lower)) return;
      if (DROP_RESPONSE_HEADERS.has(lower)) return;
      if (lower === 'set-cookie' || lower === 'location') return;
      outHeaders[lower] = upRes.headers[key];
    });
    if (upRes.headers['set-cookie']) {
      outHeaders['set-cookie'] = rewriteCookies(upRes.headers['set-cookie']);
    }
    if (upRes.headers.location) {
      outHeaders.location = rewriteLocation(upRes.headers.location, base);
    }

    status.lastStatus = upRes.statusCode;
    if (upRes.statusCode < 400) {
      status.lastOkAt = Date.now();
      status.lastError = '';
    }

    const noBody = req.method === 'HEAD' || upRes.statusCode === 204 || upRes.statusCode === 304;
    if (noBody || !isText) {
      if (!isText && upRes.headers['content-length'] && !outHeaders['content-length']) {
        outHeaders['content-length'] = upRes.headers['content-length'];
      }
      finished = true;
      res.writeHead(upRes.statusCode, outHeaders);
      if (noBody) {
        res.end();
        upRes.resume();
      } else {
        upRes.pipe(res);
      }
      return;
    }

    try {
      const buffer = await collectBody(upRes, MAX_HTML_BYTES);
      let text = rewriteText(buffer.toString('utf8'), base);
      if (isHtml) {
        const creds = config.ddmsCredentials();
        text = injectHtml(text, base, !!(creds.autoLogin && creds.username && creds.password));
      }
      const body = Buffer.from(text, 'utf8');
      outHeaders['content-type'] = ctype.indexOf('charset') === -1 && isHtml
        ? 'text/html; charset=utf-8'
        : (upRes.headers['content-type'] || 'text/plain; charset=utf-8');
      outHeaders['content-length'] = body.length;
      outHeaders['cache-control'] = isHtml ? 'no-store' : (upRes.headers['cache-control'] || 'public, max-age=3600');
      finished = true;
      res.writeHead(upRes.statusCode, outHeaders);
      res.end(req.method === 'HEAD' ? undefined : body);
    } catch (err) {
      if (!finished) {
        finished = true;
        errorPage(res, 502, 'Gagal membaca halaman DDMS: ' + err.message, base);
      }
    }
  });

  upstream.setTimeout(UPSTREAM_TIMEOUT_MS, () => {
    upstream.destroy(new Error('Waktu koneksi ke DDMS habis'));
  });

  upstream.on('error', (err) => {
    status.lastErrorAt = Date.now();
    status.lastError = err.message;
    status.lastStatus = 0;
    if (finished || res.headersSent) {
      try { res.destroy(); } catch (_e) { /* diabaikan */ }
      return;
    }
    finished = true;
    console.error('[ahass] proxy error ' + targetPath + ': ' + err.message);
    errorPage(res, 502, 'Server DDMS tidak merespons (' + err.message + ').', base);
  });

  req.on('aborted', () => upstream.destroy());
  req.pipe(upstream);
}

/* ------------------------------------------------------------------ *
 * WebSocket / upgrade (bila DDMS memakai socket realtime)
 * ------------------------------------------------------------------ */

function attachUpgrade(server) {
  server.on('upgrade', (req, socket, head) => {
    const cfg = config.get();
    const base = upstreamFor(cfg);
    if (!base) {
      socket.destroy();
      return;
    }
    const isHttps = base.protocol === 'https:';
    const transport = isHttps ? https : http;
    const path = req.url && req.url.startsWith('/') ? req.url : '/' + (req.url || '');
    const headers = Object.assign({}, req.headers, {
      host: base.host,
      origin: base.origin
    });
    const upstreamReq = transport.request({
      protocol: base.protocol,
      hostname: base.hostname,
      port: base.port || (isHttps ? 443 : 80),
      path: path,
      method: 'GET',
      headers: headers,
      agent: false,
      servername: isHttps ? base.hostname : undefined,
      rejectUnauthorized: !(cfg.ddms && cfg.ddms.allowInsecureTls)
    });

    upstreamReq.on('upgrade', (upRes, upSocket, upHead) => {
      const lines = ['HTTP/1.1 ' + (upRes.statusCode || 101) + ' ' + (upRes.statusMessage || 'Switching Protocols')];
      const raw = upRes.rawHeaders;
      for (let i = 0; i < raw.length; i += 2) {
        lines.push(raw[i] + ': ' + raw[i + 1]);
      }
      socket.write(lines.join('\r\n') + '\r\n\r\n');
      if (upHead && upHead.length) socket.write(upHead);
      if (head && head.length) upSocket.write(head);
      upSocket.pipe(socket);
      socket.pipe(upSocket);
      upSocket.on('error', () => socket.destroy());
      socket.on('error', () => upSocket.destroy());
    });

    upstreamReq.on('response', (upRes) => {
      // upstream menolak upgrade
      socket.write('HTTP/1.1 ' + (upRes.statusCode || 502) + ' Bad Gateway\r\ncontent-length: 0\r\n\r\n');
      socket.destroy();
      upRes.resume();
    });

    upstreamReq.on('error', () => socket.destroy());
    upstreamReq.end();
  });
}

module.exports = {
  proxy,
  attachUpgrade,
  proxyStatus,
  consumeLoginToken,
  issueLoginToken
};
