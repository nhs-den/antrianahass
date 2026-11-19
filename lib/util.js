'use strict';

/**
 * Utilitas kecil tanpa dependensi.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8'
};

function mimeFor(file) {
  return MIME[path.extname(file).toLowerCase()] || 'application/octet-stream';
}

function sendJson(res, code, obj) {
  const body = Buffer.from(JSON.stringify(obj));
  res.writeHead(code, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': body.length,
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff'
  });
  res.end(body);
}

function sendText(res, code, text, type) {
  const body = Buffer.from(String(text));
  res.writeHead(code, {
    'content-type': type || 'text/plain; charset=utf-8',
    'content-length': body.length,
    'cache-control': 'no-store'
  });
  res.end(body);
}

function sendError(res, code, message, extra) {
  sendJson(res, code, Object.assign({ ok: false, error: message }, extra || {}));
}

/** Baca body mentah dengan batas ukuran. */
function readBody(req, limit) {
  const max = limit || 1024 * 1024;
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    let finished = false;
    req.on('data', (chunk) => {
      if (finished) return;
      size += chunk.length;
      if (size > max) {
        finished = true;
        const err = new Error('Ukuran data terlalu besar (maks ' + Math.round(max / 1024) + ' KB)');
        err.status = 413;
        reject(err);
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (!finished) {
        finished = true;
        resolve(Buffer.concat(chunks));
      }
    });
    req.on('error', reject);
  });
}

async function readJson(req, limit) {
  const raw = await readBody(req, limit);
  if (!raw.length) return {};
  try {
    return JSON.parse(raw.toString('utf8'));
  } catch (_err) {
    const err = new Error('JSON tidak valid');
    err.status = 400;
    throw err;
  }
}

/* ------------------------------------------------------------------ *
 * Penyimpanan rahasia (password DDMS) - AES-256-GCM dengan kunci lokal
 * ------------------------------------------------------------------ */

let cachedKey = null;

function secretKey(secretPath) {
  if (cachedKey) return cachedKey;
  try {
    const raw = fs.readFileSync(secretPath);
    if (raw.length === 32) {
      cachedKey = raw;
      return cachedKey;
    }
  } catch (_err) {
    /* belum ada */
  }
  const key = crypto.randomBytes(32);
  fs.mkdirSync(path.dirname(secretPath), { recursive: true });
  fs.writeFileSync(secretPath, key, { mode: 0o600 });
  cachedKey = key;
  return key;
}

function encrypt(plain, secretPath) {
  if (!plain) return '';
  const key = secretKey(secretPath);
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ct = Buffer.concat([cipher.update(String(plain), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return 'enc1:' + iv.toString('base64url') + ':' + tag.toString('base64url') + ':' + ct.toString('base64url');
}

function decrypt(value, secretPath) {
  if (!value) return '';
  if (String(value).indexOf('enc1:') !== 0) return String(value); // kompatibilitas teks biasa
  try {
    const parts = String(value).split(':');
    const key = secretKey(secretPath);
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(parts[1], 'base64url'));
    decipher.setAuthTag(Buffer.from(parts[2], 'base64url'));
    return Buffer.concat([decipher.update(Buffer.from(parts[3], 'base64url')), decipher.final()]).toString('utf8');
  } catch (_err) {
    return '';
  }
}

/* ------------------------------------------------------------------ *
 * Cookie & keamanan
 * ------------------------------------------------------------------ */

function parseCookies(header) {
  const out = {};
  if (!header) return out;
  String(header)
    .split(';')
    .forEach((part) => {
      const idx = part.indexOf('=');
      if (idx < 1) return;
      const k = part.slice(0, idx).trim();
      const v = part.slice(idx + 1).trim();
      if (!k) return;
      try {
        out[k] = decodeURIComponent(v);
      } catch (_err) {
        out[k] = v;
      }
    });
  return out;
}

function buildCookie(name, value, opts) {
  const o = opts || {};
  const bits = [name + '=' + encodeURIComponent(value)];
  bits.push('Path=' + (o.path || '/'));
  if (o.maxAge != null) bits.push('Max-Age=' + Math.floor(o.maxAge));
  if (o.httpOnly !== false) bits.push('HttpOnly');
  bits.push('SameSite=' + (o.sameSite || 'Lax'));
  if (o.secure) bits.push('Secure');
  return bits.join('; ');
}

function timingSafeEqualStr(a, b) {
  const ba = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ba.length !== bb.length) return false;
  try {
    return crypto.timingSafeEqual(ba, bb);
  } catch (_err) {
    return false;
  }
}

/** Hanya izinkan http(s) / path lokal untuk URL yang diisi admin. */
function sanitizeUrl(input, opts) {
  const o = opts || {};
  const value = String(input || '').trim();
  if (!value) return '';
  if (value.startsWith('/') && !value.startsWith('//')) return value;
  let url;
  try {
    url = new URL(value);
  } catch (_err) {
    return '';
  }
  const allowed = o.protocols || ['http:', 'https:'];
  if (allowed.indexOf(url.protocol) === -1) return '';
  if (o.stripOrigin) {
    // dipakai untuk URL upstream: hanya butuh origin
    return url.origin;
  }
  return url.toString();
}

function log() {
  const args = Array.prototype.slice.call(arguments);
  const stamp = new Date().toISOString().replace('T', ' ').slice(0, 19);
  console.log.apply(console, ['[' + stamp + ']'].concat(args));
}

module.exports = {
  MIME,
  mimeFor,
  sendJson,
  sendText,
  sendError,
  readBody,
  readJson,
  encrypt,
  decrypt,
  parseCookies,
  buildCookie,
  timingSafeEqualStr,
  sanitizeUrl,
  log
};
