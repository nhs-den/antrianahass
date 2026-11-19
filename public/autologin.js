/* Login otomatis ke web DDMS.
   Skrip ini disuntikkan oleh proxy ke setiap halaman HTML DDMS dan hanya
   bertindak bila menemukan field password pada halaman. */
(function () {
  'use strict';

  var script = document.currentScript;
  var token = '';
  try {
    token = new URL(script.src, location.href).searchParams.get('t') || '';
  } catch (_err) {
    return;
  }
  if (!token) return;

  var creds = null;
  var attempts = 0;
  var filled = null;
  var submittedAt = 0;
  var stopped = false;
  var startedAt = Date.now();

  function visible(node) {
    if (!node) return false;
    if (node.disabled || node.readOnly) return false;
    var rect = node.getBoundingClientRect();
    if (rect.width < 2 || rect.height < 2) return false;
    var style = window.getComputedStyle(node);
    return style.visibility !== 'hidden' && style.display !== 'none' && style.opacity !== '0';
  }

  function query(selector, root) {
    if (!selector) return null;
    try {
      return (root || document).querySelector(selector);
    } catch (_err) {
      return null;
    }
  }

  function isPasswordField(node) {
    if (!node) return false;
    var type = (node.getAttribute('type') || '').toLowerCase();
    if (type === 'password') return true;
    return /pass|sandi|pwd/i.test(node.name || node.id || '');
  }

  function findPasswordField() {
    var bySelector = query(creds.passSelector);
    if (visible(bySelector)) return bySelector;
    var list = document.querySelectorAll('input');
    for (var i = 0; i < list.length; i += 1) {
      if (isPasswordField(list[i]) && visible(list[i])) return list[i];
    }
    return null;
  }

  function findUserField(passwordField) {
    var bySelector = query(creds.userSelector);
    if (visible(bySelector)) return bySelector;
    var form = passwordField && passwordField.form;
    var scope = form || document;
    var inputs = scope.querySelectorAll('input');
    var fallback = null;
    for (var i = 0; i < inputs.length; i += 1) {
      var node = inputs[i];
      var type = (node.getAttribute('type') || 'text').toLowerCase();
      if (isPasswordField(node) || !visible(node)) continue;
      if (['text', 'email', 'tel', 'number', 'search', ''].indexOf(type) === -1) continue;
      var name = (node.name || '') + ' ' + (node.id || '') + ' ' + (node.placeholder || '');
      if (/user|email|nik|login|nama|name|id|kode|username/i.test(name)) return node;
      if (!fallback) fallback = node;
    }
    return fallback;
  }

  function setValue(node, value) {
    if (!node) return false;
    try {
      var proto = node.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
      var setter = Object.getOwnPropertyDescriptor(proto, 'value');
      if (setter && setter.set) setter.set.call(node, value);
      else node.value = value;
    } catch (_err) {
      node.value = value;
    }
    try {
      node.dispatchEvent(new Event('input', { bubbles: true }));
      node.dispatchEvent(new Event('change', { bubbles: true }));
      node.dispatchEvent(new Event('blur', { bubbles: true }));
    } catch (_err) { /* diabaikan */ }
    return true;
  }

  function submit(form, passwordField) {
    var button = query(creds.submitSelector);
    if (!button && form) {
      button = form.querySelector('button[type="submit"], input[type="submit"], button:not([type])');
    }
    if (!button) {
      button = query('button[type="submit"], input[type="submit"]');
    }
    var clickable = button && visible(button) ? button : null;

    // tekan Enter pada field password (paling kompatibel dengan SPA)
    try {
      var enterOpts = { bubbles: true, cancelable: true, key: 'Enter', code: 'Enter', keyCode: 13, which: 13 };
      passwordField.dispatchEvent(new KeyboardEvent('keydown', enterOpts));
      passwordField.dispatchEvent(new KeyboardEvent('keypress', enterOpts));
      passwordField.dispatchEvent(new KeyboardEvent('keyup', enterOpts));
    } catch (_err) { /* diabaikan */ }

    if (form && typeof form.requestSubmit === 'function') {
      try { form.requestSubmit(clickable || undefined); return true; } catch (_err) { /* lanjut */ }
    }
    if (clickable) {
      clickable.click();
      return true;
    }
    if (form) {
      try { form.submit(); return true; } catch (_err) { /* lanjut */ }
    }
    return false;
  }

  function finish() {
    stopped = true;
  }

  function attempt() {
    if (stopped) return;
    if (Date.now() - startedAt > 90000) { finish(); return; }
    if (!document.body) return;

    var passwordField = findPasswordField();
    if (!passwordField) {
      // tidak ada form login di halaman ini -> tidak perlu apa-apa
      if (attempts > 0) finish();
      return;
    }

    // hindari mengulang isian bila sudah pernah submit dan tidak ada perubahan
    if (submittedAt && Date.now() - submittedAt < 6000) return;
    if (submittedAt && Date.now() - submittedAt > 25000) { finish(); return; }

    var userField = findUserField(passwordField);
    if (creds.username) setValue(userField, creds.username);
    setValue(passwordField, creds.password);
    filled = { user: !!userField, pass: true };

    setTimeout(function () {
      if (stopped) return;
      var stillThere = findPasswordField();
      if (!stillThere) { finish(); return; }
      var ok = submit(stillThere.form, stillThere);
      if (ok) {
        attempts += 1;
        submittedAt = Date.now();
        if (attempts >= 3) setTimeout(finish, 15000);
      }
    }, 220);
  }

  fetch('/__ahass/api/autologin?t=' + encodeURIComponent(token), { cache: 'no-store' })
    .then(function (res) { return res.ok ? res.json() : null; })
    .then(function (data) {
      if (!data || !data.ok || !data.username || !data.password) {
        finish();
        return;
      }
      creds = data;
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function () {
          setInterval(attempt, 900);
        });
      } else {
        attempt();
        setInterval(attempt, 900);
      }
    })
    .catch(function () { /* diam saja */ });
}());
