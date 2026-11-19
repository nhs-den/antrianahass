#!/usr/bin/env node
'use strict';

/**
 * Tiruan service ulasan-google (loader.js) untuk menguji mode "snippet".
 *   node scripts/mock-ulasan-widget.js     # http://127.0.0.1:3000/loader.js?kiosk=1
 *
 * Bila panel diarahkan ke port 3000 dan widget ini muncul di kotak ke-3,
 * berarti integrasi snippet sudah benar — tinggal ganti dengan service asli.
 */

const http = require('http');

const PORT = Number(process.env.MOCK_PORT || 3000);

const loader = `
(function () {
  var host = document.currentScript && document.currentScript.parentNode;
  if (!host) return;
  var reviews = [
    { name: 'Budi Santoso', rating: 5, text: 'Servis cepat, mekaniknya ramah.' },
    { name: 'Siti Aminah', rating: 5, text: 'Harga transparan, hasil rapi.' }
  ];
  var i = 0;
  host.innerHTML = '';
  var box = document.createElement('div');
  box.setAttribute('data-mock-ulasan', '1');
  box.style.cssText = 'height:100%;display:flex;flex-direction:column;justify-content:center;gap:4px;font:12px system-ui,sans-serif;color:#e9f1f9';
  function paint() {
    var r = reviews[i % reviews.length];
    box.innerHTML = '<div style="color:#fbbf24;font-size:11px">★★★★★</div>' +
      '<div style="line-height:1.4">“' + r.text + '”</div>' +
      '<div style="color:#8ea3b9;font-size:10px">— ' + r.name + '</div>' +
      '<div style="color:#8ea3b9;font-size:9px;opacity:.7">mock ulasan-google (port ${PORT})</div>';
  }
  paint();
  setInterval(function () { i += 1; paint(); }, 4000);
  host.appendChild(box);
}());
`;

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname === '/loader.js') {
    res.writeHead(200, {
      'content-type': 'application/javascript; charset=utf-8',
      'access-control-allow-origin': '*',
      'cache-control': 'no-store'
    });
    res.end(loader);
    return;
  }
  if (url.pathname === '/') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end('<!doctype html><meta charset="utf-8"><title>Mock ulasan-google</title>' +
      '<body style="background:#0b1017;color:#e9f1f9;font:14px system-ui">' +
      '<p>Mock service ulasan-google. Loader: <code>/loader.js?kiosk=1</code></p>' +
      '<script async src="/loader.js?kiosk=1"></script></body>');
    return;
  }
  res.writeHead(404, { 'content-type': 'text/plain' });
  res.end('not found');
});

server.listen(PORT, '0.0.0.0', () => {
  console.log('Mock ulasan-google berjalan di http://127.0.0.1:' + PORT + '/loader.js?kiosk=1');
});
