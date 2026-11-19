'use strict';

/**
 * Sesi admin sederhana: cookie HttpOnly berisi token acak,
 * disimpan di memori (hilang saat service restart = aman & ringan).
 */

const crypto = require('crypto');
const util = require('./util');
const config = require('./config');

const COOKIE = 'ahass_admin';
const SESSION_TTL_MS = 12 * 60 * 60 * 1000; // 12 jam
const sessions = new Map(); // token -> { expires, ip }
const attempts = new Map(); // ip -> { count, first, blockedUntil }

function pruneSessions() {
  const now = Date.now();
  for (const [token, sess] of sessions) {
    if (sess.expires < now) sessions.delete(token);
  }
  for (const [ip, entry] of attempts) {
    if (entry.blockedUntil && entry.blockedUntil < now && now - entry.first > 10 * 60 * 1000) {
      attempts.delete(ip);
    }
  }
}

setInterval(pruneSessions, 5 * 60 * 1000).unref();

function clientIp(req) {
  return (req.socket && req.socket.remoteAddress) || 'unknown';
}

function normalizeIp(ip) {
  return String(ip || '').replace(/^::ffff:/, '');
}

function checkRateLimit(req) {
  const ip = normalizeIp(clientIp(req));
  const entry = attempts.get(ip);
  const now = Date.now();
  if (entry && entry.blockedUntil && entry.blockedUntil > now) {
    return { blocked: true, seconds: Math.ceil((entry.blockedUntil - now) / 1000) };
  }
  return { blocked: false };
}

function noteFailure(req) {
  const ip = normalizeIp(clientIp(req));
  const now = Date.now();
  const entry = attempts.get(ip) || { count: 0, first: now, blockedUntil: 0 };
  if (now - entry.first > 10 * 60 * 1000) {
    entry.count = 0;
    entry.first = now;
    entry.blockedUntil = 0;
  }
  entry.count += 1;
  if (entry.count >= 8) entry.blockedUntil = now + 5 * 60 * 1000;
  attempts.set(ip, entry);
}

function noteSuccess(req) {
  attempts.delete(normalizeIp(clientIp(req)));
}

function createSession(req, res) {
  const token = crypto.randomBytes(24).toString('base64url');
  sessions.set(token, { expires: Date.now() + SESSION_TTL_MS, ip: normalizeIp(clientIp(req)) });
  res.setHeader(
    'set-cookie',
    util.buildCookie(COOKIE, token, { maxAge: SESSION_TTL_MS / 1000, httpOnly: true, sameSite: 'Lax' })
  );
  return token;
}

function destroySession(req, res) {
  const cookies = util.parseCookies(req.headers.cookie);
  const token = cookies[COOKIE];
  if (token) sessions.delete(token);
  res.setHeader('set-cookie', util.buildCookie(COOKIE, '', { maxAge: 0, httpOnly: true, sameSite: 'Lax' }));
}

function isAuthed(req) {
  const cookies = util.parseCookies(req.headers.cookie);
  const token = cookies[COOKIE];
  if (!token) return false;
  const sess = sessions.get(token);
  if (!sess) return false;
  if (sess.expires < Date.now()) {
    sessions.delete(token);
    return false;
  }
  return true;
}

function requireAuth(req, res) {
  if (isAuthed(req)) return true;
  util.sendError(res, 401, 'Sesi admin berakhir. Silakan login kembali.');
  return false;
}

function login(req, res, password) {
  const limit = checkRateLimit(req);
  if (limit.blocked) {
    util.sendError(res, 429, 'Terlalu banyak percobaan. Coba lagi dalam ' + limit.seconds + ' detik.');
    return false;
  }
  const cfg = config.get();
  if (!config.verifyPassword(password, cfg.admin.passwordHash, cfg.admin.passwordSalt)) {
    noteFailure(req);
    util.sendError(res, 401, 'Password salah.');
    return false;
  }
  noteSuccess(req);
  createSession(req, res);
  util.sendJson(res, 200, { ok: true });
  return true;
}

function sessionCount() {
  return sessions.size;
}

module.exports = {
  COOKIE,
  login,
  isAuthed,
  requireAuth,
  destroySession,
  sessionCount
};
