'use strict';

/**
 * Konfigurasi aplikasi.
 * Disimpan sebagai JSON di DATA_DIR/config.json sehingga bisa diedit
 * lewat halaman admin tanpa perlu restart service.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const util = require('./util');

const VERSION = require('../package.json').version;

const DATA_DIR = process.env.AHASS_DATA_DIR
  ? path.resolve(process.env.AHASS_DATA_DIR)
  : path.join(__dirname, '..', 'data');
const CONFIG_PATH = path.join(DATA_DIR, 'config.json');
const UPLOAD_DIR = path.join(DATA_DIR, 'uploads');
const SECRET_PATH = path.join(DATA_DIR, 'secret.key');
const PASSWORD_FILE = path.join(DATA_DIR, 'ADMIN-PASSWORD.txt');

function defaults() {
  return {
    version: 1,
    updatedAt: null,
    admin: {
      // hash scrypt dari password admin panel
      passwordHash: '',
      passwordSalt: '',
      passwordUpdatedAt: null
    },
    display: {
      leftPercent: 30,
      // Penskalaan seluruh panel (persen). 96 = diperkecil 4% agar tepi layar
      // tidak terpotong overscan TV.
      scalePercent: 100,
      // Geser panel dalam piksel untuk mengoreksi overscan yang tidak simetris.
      offsetX: 0,
      offsetY: 0,
      clock24: true,
      showSeconds: true,
      theme: 'dark',
      rotateSeconds: 12,
      videoSeconds: 30,
      intervalSeconds: 20,
      cursorHidden: true
    },
    logo: {
      url: '/assets/logo.png',
      title: 'AHASS Munjul Motor',
      subtitle: 'One HEART',
      tagline: 'Honda Authorized Service Station'
    },
    ddms: {
      enabled: true,
      baseUrl: 'https://web-h2-cbr.daya-dms.id',
      path: '/ddms',
      autoLogin: true,
      username: '',
      password: '',          // disimpan terenkripsi (enc1:...)
      userSelector: '',      // opsional, kosong = deteksi otomatis
      passSelector: '',
      submitSelector: '',
      reloadMinutes: 0,      // 0 = tidak pernah reload otomatis
      allowInsecureTls: false
    },
    reviews: {
      mode: 'off',           // off | script | places | ulasan | embed
      placeId: '',
      apiKey: '',
      language: 'id',
      ulasanUrl: '',
      embedUrl: '',
      maxReviews: 10,
      cacheMinutes: 60,
      showAvatar: true,
      refreshMinutes: 30,    // muat ulang kotak ulasan (mode script/embed)
      script: {
        code: '',            // snippet embed apa adanya (menang atas host/port)
        host: '',            // kosong = ikut hostname panel
        port: 3000,
        path: '/loader.js',
        query: 'kiosk=1'
      }
    },
    gallery: {
      images: [],
      videos: []
    }
  };
}

function isPlainObject(v) {
  return v && typeof v === 'object' && !Array.isArray(v);
}

function deepMerge(base, patch) {
  if (!isPlainObject(patch)) return patch === undefined ? base : patch;
  const out = isPlainObject(base) ? Object.assign({}, base) : {};
  Object.keys(patch).forEach((key) => {
    const value = patch[key];
    if (Array.isArray(value)) {
      out[key] = value.slice();
    } else if (isPlainObject(value) && isPlainObject(out[key])) {
      out[key] = deepMerge(out[key], value);
    } else if (value !== undefined) {
      out[key] = value;
    }
  });
  return out;
}

function ensureDirs() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.mkdirSync(UPLOAD_DIR, { recursive: true });
}

/* ------------------------------------------------------------------ */
/* Password admin                                                      */
/* ------------------------------------------------------------------ */

function hashPassword(password, salt) {
  const useSalt = salt || crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(String(password), useSalt, 32, { N: 16384, r: 8, p: 1 }).toString('hex');
  return { hash, salt: useSalt };
}

function verifyPassword(password, hash, salt) {
  if (!hash || !salt) return false;
  try {
    const candidate = crypto.scryptSync(String(password), salt, 32, { N: 16384, r: 8, p: 1 }).toString('hex');
    return util.timingSafeEqualStr(candidate, hash);
  } catch (_err) {
    return false;
  }
}

function generatePassword() {
  // hindari karakter yang membingungkan saat diketik ulang
  const alphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = crypto.randomBytes(10);
  let out = '';
  for (let i = 0; i < bytes.length; i += 1) out += alphabet[bytes[i] % alphabet.length];
  return out;
}

function bootstrapAdminPassword(cfg) {
  const envPassword = process.env.AHASS_ADMIN_PASSWORD;
  if (cfg.admin.passwordHash) {
    // izinkan reset via env (berguna saat lupa password pada unit kiosk)
    if (envPassword && !verifyPassword(envPassword, cfg.admin.passwordHash, cfg.admin.passwordSalt)) {
      const res = hashPassword(envPassword);
      cfg.admin.passwordHash = res.hash;
      cfg.admin.passwordSalt = res.salt;
      cfg.admin.passwordUpdatedAt = new Date().toISOString();
      console.log('[ahass] Password admin direset dari variabel AHASS_ADMIN_PASSWORD');
      return { changed: true, generated: null };
    }
    return { changed: false, generated: null };
  }
  const password = envPassword || generatePassword();
  const res = hashPassword(password);
  cfg.admin.passwordHash = res.hash;
  cfg.admin.passwordSalt = res.salt;
  cfg.admin.passwordUpdatedAt = new Date().toISOString();
  if (!envPassword) {
    try {
      fs.writeFileSync(
        PASSWORD_FILE,
        'Password admin panel AHASS\n' + '='.repeat(30) + '\n' +
          'Password : ' + password + '\n' +
          'Alamat   : http://<ip-kiosk>:8080/admin\n' +
          'Dibuat   : ' + new Date().toString() + '\n\n' +
          'Ganti password ini melalui menu "Keamanan" di halaman admin.\n' +
          'File ini boleh dihapus setelah password dicatat.\n',
        { mode: 0o600 }
      );
    } catch (_err) {
      /* diabaikan */
    }
    console.log('\n=====================================================');
    console.log('  PASSWORD ADMIN PANEL (pertama kali dijalankan):');
    console.log('  ==>  ' + password + '  <==');
    console.log('  Login di: /admin  (file: ' + PASSWORD_FILE + ')');
    console.log('=====================================================\n');
  }
  return { changed: true, generated: envPassword ? null : password };
}

function setAdminPassword(cfg, password) {
  const res = hashPassword(password);
  cfg.admin.passwordHash = res.hash;
  cfg.admin.passwordSalt = res.salt;
  cfg.admin.passwordUpdatedAt = new Date().toISOString();
}

/* ------------------------------------------------------------------ */
/* Muat / simpan                                                       */
/* ------------------------------------------------------------------ */

let current = null;

function migrate(cfg) {
  // nilai default yang belum ada pada file lama
  const base = defaults();
  const merged = deepMerge(base, cfg);
  merged.admin = Object.assign({}, base.admin, cfg.admin || {});
  merged.version = 1;
  return merged;
}

function load() {
  ensureDirs();
  let onDisk = {};
  try {
    onDisk = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
  } catch (err) {
    if (err.code !== 'ENOENT') {
      console.error('[ahass] config.json rusak, memakai default:', err.message);
      try {
        fs.copyFileSync(CONFIG_PATH, CONFIG_PATH + '.broken-' + Date.now());
      } catch (_e) { /* diabaikan */ }
    }
  }
  current = migrate(onDisk || {});
  const boot = bootstrapAdminPassword(current);
  if (boot.changed) persist();
  // simpan juga jika ada field baru dari versi sebelumnya
  if (!fs.existsSync(CONFIG_PATH)) persist();
  if (!Array.isArray(current.gallery.images)) current.gallery.images = [];
  if (!Array.isArray(current.gallery.videos)) current.gallery.videos = [];
  return current;
}

function persist() {
  if (!current) return;
  ensureDirs();
  current.updatedAt = new Date().toISOString();
  const tmp = CONFIG_PATH + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(current, null, 2), { mode: 0o600 });
  fs.renameSync(tmp, CONFIG_PATH);
}

function get() {
  if (!current) load();
  return current;
}

function update(patch) {
  const cfg = get();
  current = deepMerge(cfg, patch || {});
  persist();
  return current;
}

/** Password DDMS dalam bentuk asli. */
function ddmsPassword() {
  return util.decrypt(get().ddms.password, SECRET_PATH);
}

function ddmsCredentials() {
  const cfg = get();
  return {
    username: cfg.ddms.username || '',
    password: ddmsPassword(),
    userSelector: cfg.ddms.userSelector || '',
    passSelector: cfg.ddms.passSelector || '',
    submitSelector: cfg.ddms.submitSelector || '',
    autoLogin: !!cfg.ddms.autoLogin,
    enabled: !!cfg.ddms.enabled
  };
}

function publicConfig() {
  const cfg = get();
  return {
    version: VERSION,
    display: cfg.display,
    logo: cfg.logo,
    ddms: {
      enabled: !!cfg.ddms.enabled,
      path: cfg.ddms.path || '/ddms',
      autoLogin: !!cfg.ddms.autoLogin && !!(cfg.ddms.username && ddmsPassword()),
      reloadMinutes: cfg.ddms.reloadMinutes || 0
    },
    reviews: {
      mode: cfg.reviews.mode,
      embedUrl: cfg.reviews.embedUrl,
      language: cfg.reviews.language,
      showAvatar: !!cfg.reviews.showAvatar,
      refreshMinutes: cfg.reviews.refreshMinutes,
      scriptUrl: cfg.reviews.mode === 'script' ? '/__ahass/ulasan' : ''
    },
    gallery: cfg.gallery
  };
}

/** Konfigurasi untuk admin - tanpa membocorkan rahasia. */
function adminConfig() {
  const cfg = get();
  return {
    version: VERSION,
    display: cfg.display,
    logo: cfg.logo,
    ddms: {
      enabled: !!cfg.ddms.enabled,
      baseUrl: cfg.ddms.baseUrl,
      path: cfg.ddms.path,
      autoLogin: !!cfg.ddms.autoLogin,
      username: cfg.ddms.username,
      passwordSet: !!ddmsPassword(),
      userSelector: cfg.ddms.userSelector,
      passSelector: cfg.ddms.passSelector,
      submitSelector: cfg.ddms.submitSelector,
      reloadMinutes: cfg.ddms.reloadMinutes,
      allowInsecureTls: !!cfg.ddms.allowInsecureTls
    },
    reviews: {
      mode: cfg.reviews.mode,
      placeId: cfg.reviews.placeId,
      apiKeySet: !!cfg.reviews.apiKey,
      language: cfg.reviews.language,
      ulasanUrl: cfg.reviews.ulasanUrl,
      embedUrl: cfg.reviews.embedUrl,
      maxReviews: cfg.reviews.maxReviews,
      cacheMinutes: cfg.reviews.cacheMinutes,
      showAvatar: !!cfg.reviews.showAvatar,
      refreshMinutes: cfg.reviews.refreshMinutes,
      script: cfg.reviews.script
    },
    gallery: cfg.gallery,
    updatedAt: cfg.updatedAt,
    passwordUpdatedAt: cfg.admin.passwordUpdatedAt
  };
}

module.exports = {
  VERSION,
  DATA_DIR,
  CONFIG_PATH,
  UPLOAD_DIR,
  SECRET_PATH,
  PASSWORD_FILE,
  defaults,
  deepMerge,
  load,
  get,
  update,
  persist,
  save: persist,
  ensureDirs,
  hashPassword,
  verifyPassword,
  generatePassword,
  setAdminPassword,
  ddmsPassword,
  ddmsCredentials,
  publicConfig,
  adminConfig
};
