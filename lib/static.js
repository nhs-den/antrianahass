'use strict';

/**
 * Penyaji file statis minimalis dengan dukungan ETag/304.
 */

const fs = require('fs');
const path = require('path');
const util = require('./util');

const PUBLIC_DIR = path.join(__dirname, '..', 'public');

function resolveSafe(rootDir, relPath) {
  const clean = String(relPath || '').split('?')[0].split('#')[0];
  const decoded = decodeURIComponent(clean);
  const full = path.normalize(path.join(rootDir, decoded));
  if (full !== rootDir && !full.startsWith(rootDir + path.sep)) return null;
  return full;
}

function isLongLivedAsset(file) {
  return /\.(png|jpe?g|webp|gif|svg|ico|woff2?|ttf)$/i.test(file);
}

function send(res, relPath, opts) {
  const o = opts || {};
  const rootDir = o.root || PUBLIC_DIR;
  const full = resolveSafe(rootDir, relPath);
  if (!full) {
    util.sendText(res, 400, 'Bad request');
    return;
  }
  fs.stat(full, (err, stat) => {
    if (err || !stat.isFile()) {
      util.sendText(res, 404, 'Not found');
      return;
    }
    const etag = 'W/"' + stat.size.toString(16) + '-' + Math.floor(stat.mtimeMs).toString(16) + '"';
    if (o.cache && !o.nocache && res.req && res.req.headers['if-none-match'] === etag) {
      res.writeHead(304, {
        etag: etag,
        'cache-control': isLongLivedAsset(full) ? 'public, max-age=86400' : 'no-cache'
      });
      res.end();
      return;
    }
    const longLived = isLongLivedAsset(full);
    const headers = {
      'content-type': util.mimeFor(full),
      'content-length': stat.size,
      // HTML/JS/CSS harus revalidasi (murah, lokal) supaya update langsung tampil;
      // gambar/ikon boleh disimpan di cache lebih lama.
      'cache-control': o.nocache || !o.cache
        ? 'no-store'
        : (longLived ? 'public, max-age=86400' : 'no-cache'),
      etag: etag,
      'last-modified': stat.mtime.toUTCString(),
      'x-content-type-options': 'nosniff'
    };
    res.writeHead(200, headers);
    if (res.req && res.req.method === 'HEAD') {
      res.end();
      return;
    }
    fs.createReadStream(full)
      .on('error', () => {
        try { res.destroy(); } catch (_e) { /* diabaikan */ }
      })
      .pipe(res);
  });
}

function exists(relPath) {
  const full = resolveSafe(PUBLIC_DIR, relPath);
  return !!(full && fs.existsSync(full));
}

module.exports = { send, exists, PUBLIC_DIR };
