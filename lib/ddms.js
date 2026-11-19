'use strict';

/**
 * Pemeriksaan koneksi ke web DDMS dari sisi server.
 * Dipakai tombol "Tes koneksi / Tes login" di halaman admin.
 */

const http = require('http');
const https = require('https');
const config = require('./config');

function request(urlString, options) {
  const o = options || {};
  return new Promise((resolve, reject) => {
    let url;
    try {
      url = new URL(urlString);
    } catch (_err) {
      reject(new Error('URL tidak valid: ' + urlString));
      return;
    }
    const isHttps = url.protocol === 'https:';
    const transport = isHttps ? https : http;
    const headers = Object.assign({ 'user-agent': 'Mozilla/5.0 (X11; Linux x86_64) ahass-panel/1.0', accept: 'text/html,*/*' }, o.headers || {});
    const req = transport.request(
      {
        protocol: url.protocol,
        hostname: url.hostname,
        port: url.port || (isHttps ? 443 : 80),
        path: url.pathname + url.search,
        method: o.method || 'GET',
        headers: headers,
        timeout: o.timeout || 15000,
        servername: isHttps ? url.hostname : undefined,
        rejectUnauthorized: !(config.get().ddms.allowInsecureTls)
      },
      (res) => {
        const chunks = [];
        let size = 0;
        res.on('data', (c) => {
          size += c.length;
          if (size < 2 * 1024 * 1024) chunks.push(c);
        });
        res.on('end', () => {
          resolve({
            status: res.statusCode,
            headers: res.headers,
            body: Buffer.concat(chunks).toString('utf8')
          });
        });
      }
    );
    req.on('timeout', () => req.destroy(new Error('Timeout (' + ((o.timeout || 15000) / 1000) + 's)')));
    req.on('error', reject);
    if (o.body) req.write(o.body);
    req.end();
  });
}

function cookiesFrom(res) {
  const raw = res.headers['set-cookie'];
  if (!raw) return '';
  return raw.map((c) => String(c).split(';')[0]).join('; ');
}

function parseForm(html) {
  const form = { action: '', method: 'post', fields: {}, hidden: {} };
  const formMatch = html.match(/<form\b[^>]*>/i);
  if (formMatch) {
    const action = formMatch[0].match(/action\s*=\s*["']([^"']*)["']/i);
    if (action) form.action = action[1];
    const method = formMatch[0].match(/method\s*=\s*["']([^"']*)["']/i);
    if (method) form.method = method[1].toLowerCase();
  }
  const inputRe = /<input\b[^>]*>/gi;
  let m;
  let passwordField = '';
  const candidates = [];
  while ((m = inputRe.exec(html))) {
    const tag = m[0];
    const name = (tag.match(/name\s*=\s*["']([^"']+)["']/i) || [])[1];
    if (!name) continue;
    const type = ((tag.match(/type\s*=\s*["']([^"']+)["']/i) || [])[1] || 'text').toLowerCase();
    const value = (tag.match(/value\s*=\s*["']([^"']*)["']/i) || [])[1] || '';
    if (type === 'hidden') form.hidden[name] = value;
    else if (type === 'password' && !passwordField) passwordField = name;
    else if (['text', 'email', 'tel', 'number', ''].indexOf(type) !== -1) candidates.push(name);
  }
  form.fields.password = passwordField;
  form.fields.username =
    candidates.find((n) => /user|email|nik|login|nama|name|id/i.test(n)) || candidates[0] || '';
  form.allTextFields = candidates;
  return form;
}

async function testLogin() {
  const creds = config.ddmsCredentials();
  const cfg = config.get();
  const base = cfg.ddms.baseUrl.replace(/\/+$/, '');
  const startUrl = base + (cfg.ddms.path || '/ddms');
  const steps = [];

  const first = await request(startUrl, { timeout: 15000 });
  steps.push({ step: 'buka halaman login', status: first.status, url: startUrl });
  if (first.status >= 400) {
    return { ok: false, steps: steps, message: 'Halaman login membalas HTTP ' + first.status };
  }

  const form = parseForm(first.body);
  const hasPasswordField = !!form.fields.password || /type\s*=\s*["']password["']/i.test(first.body);
  steps.push({
    step: 'deteksi form',
    action: form.action || '(halaman ini)',
    fieldUser: form.fields.username || '(tidak ketemu)',
    fieldPass: form.fields.password || '(tidak ketemu)'
  });

  if (!hasPasswordField) {
    return {
      ok: true,
      steps: steps,
      message: 'Halaman tidak menampilkan form password — kemungkinan sudah dalam keadaan login (belum ada sesi).'
    };
  }

  const actionUrl = new URL(form.action || startUrl, startUrl).toString();
  const body = new URLSearchParams(Object.assign({}, form.hidden,
    form.fields.username ? { [form.fields.username]: creds.username } : {},
    form.fields.password ? { [form.fields.password]: creds.password } : {}
  )).toString();

  const cookie = cookiesFrom(first);
  const login = await request(actionUrl, {
    method: 'POST',
    headers: Object.assign(
      {
        'content-type': 'application/x-www-form-urlencoded',
        'content-length': Buffer.byteLength(body),
        referer: startUrl,
        origin: new URL(startUrl).origin
      },
      cookie ? { cookie: cookie } : {}
    ),
    body: body,
    timeout: 20000
  });

  const setCookies = login.headers['set-cookie'] || [];
  const stillHasPassword = /type\s*=\s*["']password["']/i.test(login.body || '');
  const redirect = login.headers.location || '';
  const success = setCookies.length > 0 || (!stillHasPassword && (login.status === 302 || login.status === 303 || login.status === 200));

  steps.push({
    step: 'kirim kredensial',
    status: login.status,
    redirect: redirect || null,
    cookiesReceived: setCookies.map((c) => String(c).split('=')[0]).join(', ') || '(tidak ada)',
    masihAdaFormPassword: stillHasPassword
  });

  return {
    ok: success,
    steps: steps,
    message: success
      ? 'Login tampaknya berhasil (sesi/cookie diterima). Panel akan login otomatis saat menampilkan DDMS.'
      : 'Login belum berhasil. Periksa user/password, atau isi selector form secara manual.'
  };
}

async function ping() {
  const cfg = config.get();
  const base = cfg.ddms.baseUrl.replace(/\/+$/, '');
  const started = Date.now();
  try {
    const res = await request(base + (cfg.ddms.path || '/ddms'), { timeout: 10000, method: 'GET' });
    return {
      ok: res.status < 500,
      status: res.status,
      ms: Date.now() - started,
      url: base
    };
  } catch (err) {
    return { ok: false, status: 0, ms: Date.now() - started, url: base, error: err.message };
  }
}

module.exports = { ping, testLogin, parseForm };
