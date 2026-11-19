'use strict';

/**
 * Halaman kecil untuk menampilkan widget ulasan-google (loader.js).
 *
 * Widget dijalankan di dalam iframe supaya CSS/JS-nya tidak bisa mengganggu
 * panel kiosk (dan sebaliknya). Halaman ini memakai snippet embed yang
 * ditempel admin, atau membuat snippet standar dari host/port/path.
 */

function escapeHtml(text) {
  return String(text == null ? '' : text)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function escapeJs(text) {
  return String(text == null ? '' : text).replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

/**
 * Snippet standar ulasan-google:
 *   <script>...src='http://'+(location.hostname||'127.0.0.1')+':3000/loader.js?kiosk=1'...</script>
 */
function buildSnippet(script) {
  const s = script || {};
  const port = Number(s.port) || 3000;
  const path = s.path || '/loader.js';
  const query = s.query ? (String(s.query).charAt(0) === '?' ? String(s.query) : '?' + String(s.query)) : '';
  const hostExpr = s.host
    ? "'http://" + escapeJs(s.host) + "'"
    : "'http://'+(location.hostname||'127.0.0.1')";

  return (
    '<script>(function(){var p=document.currentScript.parentNode;function l(){' +
    'var s=document.createElement(\'script\');s.async=true;' +
    's.src=' + hostExpr + '+' + JSON.stringify(':' + port + path + query) + ';' +
    's.onerror=function(){s.remove();setTimeout(l,3000);};p.appendChild(s);}l();})();<\/script>'
  );
}

function render(cfg) {
  const reviews = (cfg && cfg.reviews) || {};
  const script = reviews.script || {};
  const code = String(script.code || '').trim();
  const snippet = code || buildSnippet(script);
  const theme = (cfg && cfg.display && cfg.display.theme) === 'light' ? 'light' : 'dark';
  const target =
    'http://' + (script.host || '127.0.0.1') + ':' + (Number(script.port) || 3000) + (script.path || '/loader.js');

  return `<!DOCTYPE html>
<html lang="id" data-theme="${theme}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="${theme}">
<title>Ulasan Google</title>
<style>
  html, body {
    margin: 0;
    height: 100%;
    overflow: hidden;
    background: transparent;
    color: ${theme === 'light' ? '#0d1b2a' : '#e9f1f9'};
    font-family: "DejaVu Sans", system-ui, -apple-system, "Segoe UI", Roboto, Arial, sans-serif;
    font-size: 12px;
  }
  #w { height: 100%; width: 100%; display: flex; flex-direction: column; justify-content: center; }
  #w > * { max-width: 100%; }
  #fallback {
    position: fixed;
    inset: 0;
    display: none;
    align-items: center;
    justify-content: center;
    text-align: center;
    padding: 10px;
    line-height: 1.45;
    color: ${theme === 'light' ? '#5b7085' : '#8ea3b9'};
    font-size: 11px;
  }
  #fallback.show { display: flex; }
  #fallback code { color: ${theme === 'light' ? '#0d1b2a' : '#e9f1f9'}; }
</style>
</head>
<body>
<div id="w">${snippet}</div>
<div id="fallback">
  <div>
    Widget ulasan belum termuat.<br>
    Pastikan aplikasi <b>ulasan-google</b> berjalan di <code>${escapeHtml(target)}</code>.
  </div>
</div>
<script>
  (function () {
    var wrap = document.getElementById('w');
    var fallback = document.getElementById('fallback');
    var tries = 0;
    function check() {
      tries += 1;
      var nodes = wrap.children ? wrap.children.length : 0;
      // loader.js yang gagal akan menghapus dirinya sendiri; bila tetap kosong
      // berarti widget belum tampil.
      if (nodes > 0) { fallback.className = ''; return; }
      if (tries > 3) fallback.className = 'show';
      if (tries < 12) setTimeout(check, 2500);
    }
    setTimeout(check, 2500);
  }());
</script>
</body>
</html>`;
}

module.exports = { render, buildSnippet };
