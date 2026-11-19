#!/usr/bin/env node
'use strict';

/**
 * Server DDMS tiruan untuk menguji reverse proxy + login otomatis
 * tanpa menyentuh server produksi.
 *
 *   node scripts/mock-ddms.js            # port 9099
 *   MOCK_PORT=9100 node scripts/mock-ddms.js
 *
 * Login yang diterima: admin / rahasia123
 */

const http = require('http');

const PORT = Number(process.env.MOCK_PORT || 9099);
const HOST = '127.0.0.1:' + PORT;

function loginPage(message) {
  return `<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'self'">
<title>Login DDMS</title>
<link rel="stylesheet" href="/static/app.css">
</head><body>
<h1>${message || 'Silakan login'}</h1>
<img src="http://${HOST}/static/logo.png">
<form method="post" action="/ddms/login">
  <input type="hidden" name="csrf" value="abc123">
  <input type="text" name="username" placeholder="Username">
  <input type="password" name="password" placeholder="Password">
  <button type="submit">Masuk</button>
</form>
<script>fetch('http://${HOST}/api/ping');</script>
</body></html>`;
}

function homePage() {
  return `<!doctype html><html><head><meta charset="utf-8"><title>DDMS Home</title></head>
<body><h1>Selamat datang di DDMS</h1>
<a href="/ddms/antrian">Antrian</a>
<a href="http://${HOST}/ddms/laporan">Laporan</a>
</body></html>`;
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const cookies = req.headers.cookie || '';

  if (url.pathname === '/ddms/login' && req.method === 'POST') {
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      const params = new URLSearchParams(body);
      const valid =
        params.get('username') === 'admin' &&
        params.get('password') === 'rahasia123' &&
        params.get('csrf') === 'abc123';
      if (valid) {
        res.writeHead(302, {
          location: 'http://' + HOST + '/ddms/',
          'set-cookie': 'JSESSIONID=xyz; Path=/; Domain=127.0.0.1; Secure; HttpOnly; SameSite=None',
          'content-security-policy': "default-src 'self'",
          'x-frame-options': 'DENY'
        });
        res.end();
      } else {
        res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
        res.end(loginPage('Password salah, coba lagi'));
      }
    });
    return;
  }

  if (url.pathname === '/ddms/login') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(loginPage());
    return;
  }

  if (url.pathname === '/ddms' || url.pathname === '/ddms/' || url.pathname === '/ddms/antrian') {
    if (cookies.indexOf('JSESSIONID=xyz') === -1) {
      res.writeHead(302, { location: '/ddms/login' });
      res.end();
      return;
    }
    res.writeHead(200, {
      'content-type': 'text/html; charset=utf-8',
      'x-frame-options': 'SAMEORIGIN',
      'content-security-policy': "default-src 'self'",
      'set-cookie': 'PREF=id; Path=/; Secure'
    });
    res.end(homePage());
    return;
  }

  if (url.pathname === '/static/app.css') {
    res.writeHead(200, { 'content-type': 'text/css' });
    res.end('body{background:url("http://' + HOST + '/static/bg.png")}');
    return;
  }

  if (url.pathname === '/api/ping') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ url: 'http://' + HOST + '/api/ping' }));
    return;
  }

  res.writeHead(404, { 'content-type': 'text/html' });
  res.end('<h1>404</h1>');
});

server.listen(PORT, '0.0.0.0', () => {
  console.log('Mock DDMS berjalan di http://' + HOST + '/ddms (login: admin / rahasia123)');
});
