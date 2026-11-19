/* Halaman admin Panel AHASS */
(function () {
  'use strict';

  var $ = function (id) { return document.getElementById(id); };

  var state = {
    cfg: null,
    images: [],
    videos: [],
    status: null,
    reviewMode: 'off'
  };

  var toastTimer = null;

  /* ---------------------------------------------------------------- util */

  function toast(message, kind) {
    var el = $('toast');
    el.textContent = message;
    el.className = 'toast' + (kind ? ' ' + kind : '');
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.hidden = true; }, 4200);
  }

  function escapeHtml(text) {
    return String(text == null ? '' : text)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function api(path, options) {
    var opts = options || {};
    var init = {
      method: opts.method || 'GET',
      cache: 'no-store',
      credentials: 'same-origin',
      headers: { accept: 'application/json' }
    };
    if (opts.body !== undefined) {
      init.headers['content-type'] = 'application/json';
      init.body = JSON.stringify(opts.body);
    }
    return fetch('/__ahass/api/' + path, init).then(function (res) {
      return res.json().catch(function () { return {}; }).then(function (data) {
        if (res.status === 401) {
          showLogin();
          throw new Error(data.error || 'Perlu login ulang.');
        }
        if (!res.ok) throw new Error(data.error || ('HTTP ' + res.status));
        return data;
      });
    });
  }

  function setMsg(el, text, ok) {
    el.textContent = text || '';
    el.className = 'form-msg' + (ok ? ' ok' : '');
  }

  /* --------------------------------------------------------------- views */

  function showLogin() {
    $('loginView').hidden = false;
    $('appView').hidden = true;
    setTimeout(function () { $('loginPassword').focus(); }, 60);
  }

  function showApp() {
    $('loginView').hidden = true;
    $('appView').hidden = false;
  }

  /* --------------------------------------------------------------- tabs */

  function setupTabs() {
    var tabs = $('tabs');
    tabs.addEventListener('click', function (event) {
      var btn = event.target.closest('.tab');
      if (!btn) return;
      var target = btn.getAttribute('data-target');
      Array.prototype.forEach.call(tabs.querySelectorAll('.tab'), function (t) {
        t.classList.toggle('is-active', t === btn);
      });
      Array.prototype.forEach.call(document.querySelectorAll('.panel'), function (p) {
        p.classList.toggle('is-active', p.getAttribute('data-panel') === target);
      });
      if (target === 'status') loadStatus();
    });
  }

  /* -------------------------------------------------------------- config */

  function fillForm(cfg) {
    state.cfg = cfg;
    state.images = (cfg.gallery.images || []).slice();
    state.videos = (cfg.gallery.videos || []).slice();

    $('versionLabel').textContent = 'v' + cfg.version;
    $('panelUrl').textContent = location.origin + '/';

    // DDMS
    $('dEnabled').checked = !!cfg.ddms.enabled;
    $('dBaseUrl').value = cfg.ddms.baseUrl || '';
    $('dPath').value = cfg.ddms.path || '';
    $('dAutoLogin').checked = !!cfg.ddms.autoLogin;
    $('dUser').value = cfg.ddms.username || '';
    $('dPass').value = '';
    $('dUserSel').value = cfg.ddms.userSelector || '';
    $('dPassSel').value = cfg.ddms.passSelector || '';
    $('dSubmitSel').value = cfg.ddms.submitSelector || '';
    $('dReload').value = cfg.ddms.reloadMinutes || 0;
    $('dInsecure').checked = !!cfg.ddms.allowInsecureTls;
    $('passHint').textContent = cfg.ddms.passwordSet
      ? 'Password tersimpan. Kosongkan bila tidak ingin mengubah.'
      : 'Belum ada password tersimpan.';

    // Logo
    $('lUrl').value = cfg.logo.url || '';
    $('lTitle').value = cfg.logo.title || '';
    $('lSub').value = cfg.logo.subtitle || '';
    $('lTagline').value = cfg.logo.tagline || '';
    $('logoPreview').src = cfg.logo.url || '/assets/logo.png';

    // Reviews
    state.reviewMode = cfg.reviews.mode || 'off';
    setSelect('rMode', state.reviewMode);
    $('rPlaceId').value = cfg.reviews.placeId || '';
    $('rApiKey').value = '';
    $('apiKeyHint').textContent = cfg.reviews.apiKeySet
      ? 'API key tersimpan. Kosongkan bila tidak diubah.'
      : 'Belum ada API key.';
    $('rLang').value = cfg.reviews.language || 'id';
    $('rUlasanUrl').value = cfg.reviews.ulasanUrl || '';
    $('rEmbedUrl').value = cfg.reviews.embedUrl || '';
    $('rMax').value = cfg.reviews.maxReviews || 10;
    $('rCache').value = cfg.reviews.cacheMinutes || 60;
    $('rRefresh').value = cfg.reviews.refreshMinutes != null ? cfg.reviews.refreshMinutes : 30;
    var rs = cfg.reviews.script || {};
    $('rScriptCode').value = rs.code || '';
    $('rScriptPort').value = rs.port || 3000;
    $('rScriptPath').value = rs.path || '/loader.js';
    $('rScriptQuery').value = rs.query || 'kiosk=1';
    $('rScriptHost').value = rs.host || '';
    $('rAvatar').checked = !!cfg.reviews.showAvatar;
    updateModeFields();

    // Display
    $('dLeft').value = cfg.display.leftPercent || 30;
    $('leftValue').textContent = ($('dLeft').value) + '%';
    $('dRotate').value = cfg.display.rotateSeconds || 12;
    $('dVideo').value = cfg.display.videoSeconds || 30;
    setSelect('dTheme', cfg.display.theme || 'dark');
    $('dClock24').checked = cfg.display.clock24 !== false;
    $('dSeconds').checked = cfg.display.showSeconds !== false;
    $('dCursor').checked = cfg.display.cursorHidden !== false;

    // Security
    $('passwordUpdatedHint').textContent = cfg.passwordUpdatedAt
      ? 'Terakhir diubah: ' + new Date(cfg.passwordUpdatedAt).toLocaleString('id-ID')
      : '';

    renderGallery('images');
    renderGallery('videos');
  }

  function setSelect(id, value) {
    var el = $(id);
    if (!el) return;
    try {
      el.value = value;
    } catch (_err) { /* abaikan */ }
    if (el.value !== value) {
      var opts = el.options || el.querySelectorAll('option');
      for (var i = 0; i < opts.length; i += 1) {
        opts[i].selected = opts[i].value === value;
      }
    }
  }

  function getSelect(id) {
    var el = $(id);
    if (!el) return '';
    if (el.value) return el.value;
    var selected = el.querySelector('option[selected]') || el.options && el.options[el.selectedIndex];
    return (selected && selected.value) || '';
  }

  function updateModeFields() {
    var mode = state.reviewMode || getSelect('rMode');
    Array.prototype.forEach.call(document.querySelectorAll('[data-mode]'), function (el) {
      el.hidden = el.getAttribute('data-mode') !== mode;
    });
  }

  function collect() {
    return {
      display: {
        leftPercent: Number($('dLeft').value),
        clock24: $('dClock24').checked,
        showSeconds: $('dSeconds').checked,
        theme: getSelect('dTheme') || 'dark',
        rotateSeconds: Number($('dRotate').value),
        videoSeconds: Number($('dVideo').value),
        cursorHidden: $('dCursor').checked
      },
      logo: {
        url: $('lUrl').value.trim() || '/assets/logo.png',
        title: $('lTitle').value.trim(),
        subtitle: $('lSub').value.trim(),
        tagline: $('lTagline').value.trim()
      },
      ddms: {
        enabled: $('dEnabled').checked,
        baseUrl: $('dBaseUrl').value.trim(),
        path: $('dPath').value.trim(),
        autoLogin: $('dAutoLogin').checked,
        username: $('dUser').value.trim(),
        password: $('dPass').value,
        userSelector: $('dUserSel').value.trim(),
        passSelector: $('dPassSel').value.trim(),
        submitSelector: $('dSubmitSel').value.trim(),
        reloadMinutes: Number($('dReload').value) || 0,
        allowInsecureTls: $('dInsecure').checked
      },
      reviews: {
        mode: state.reviewMode || getSelect('rMode') || 'off',
        placeId: $('rPlaceId').value.trim(),
        apiKey: $('rApiKey').value,
        language: $('rLang').value.trim() || 'id',
        ulasanUrl: $('rUlasanUrl').value.trim(),
        embedUrl: $('rEmbedUrl').value.trim(),
        maxReviews: Number($('rMax').value) || 10,
        cacheMinutes: Number($('rCache').value) || 60,
        refreshMinutes: Number($('rRefresh').value) || 0,
        showAvatar: $('rAvatar').checked,
        script: {
          code: $('rScriptCode').value,
          host: $('rScriptHost').value.trim(),
          port: Number($('rScriptPort').value) || 3000,
          path: $('rScriptPath').value.trim() || '/loader.js',
          query: $('rScriptQuery').value.trim()
        }
      },
      gallery: {
        images: state.images,
        videos: state.videos
      }
    };
  }

  function save(silent) {
    var btn = $('saveBtn');
    btn.disabled = true;
    return api('admin/config', { method: 'PUT', body: collect() })
      .then(function (res) {
        if (res.config) fillForm(res.config);
        if (!silent) toast('Perubahan tersimpan. Panel kiosk diperbarui otomatis.', 'ok');
        return res;
      })
      .catch(function (err) {
        toast('Gagal menyimpan: ' + err.message, 'bad');
        throw err;
      })
      .finally(function () { btn.disabled = false; });
  }

  /* -------------------------------------------------------------- gallery */

  function galleryFor(kind) {
    return kind === 'images' ? state.images : state.videos;
  }

  function renderGallery(kind) {
    var list = $(kind === 'images' ? 'imageList' : 'videoList');
    var items = galleryFor(kind);
    list.innerHTML = '';
    if (!items.length) return;

    items.forEach(function (item, index) {
      var li = document.createElement('li');
      li.className = 'item';

      var thumb = document.createElement('div');
      thumb.className = 'item-thumb';
      var isImage = /\.(png|jpe?g|webp|gif|avif)(\?|$)/i.test(item.url);
      if (isImage) {
        var img = document.createElement('img');
        img.src = item.url;
        img.alt = '';
        img.loading = 'lazy';
        thumb.appendChild(img);
      } else {
        thumb.textContent = kind === 'videos' ? '▶' : '🖼';
      }

      var info = document.createElement('div');
      info.className = 'item-info';
      info.innerHTML = '<span class="url">' + escapeHtml(item.url) + '</span>' +
        (item.caption ? '<span class="cap">' + escapeHtml(item.caption) + '</span>' : '');

      var actions = document.createElement('div');
      actions.className = 'item-actions';
      actions.appendChild(iconButton('↑', 'Naikkan', function () { moveItem(kind, index, -1); }));
      actions.appendChild(iconButton('↓', 'Turunkan', function () { moveItem(kind, index, 1); }));
      actions.appendChild(iconButton('✕', 'Hapus', function () { removeItem(kind, index); }, 'del'));

      li.appendChild(thumb);
      li.appendChild(info);
      li.appendChild(actions);
      list.appendChild(li);
    });
  }

  function iconButton(label, title, handler, extraClass) {
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'icon-btn' + (extraClass ? ' ' + extraClass : '');
    btn.title = title;
    btn.textContent = label;
    btn.addEventListener('click', handler);
    return btn;
  }

  function addItem(kind) {
    var urlInput = $(kind === 'images' ? 'giUrl' : 'gvUrl');
    var capInput = $(kind === 'images' ? 'giCaption' : 'gvCaption');
    var url = urlInput.value.trim();
    if (!url) {
      toast('Link belum diisi.', 'bad');
      urlInput.focus();
      return;
    }
    if (!/^https?:\/\//i.test(url) && url.charAt(0) !== '/') {
      toast('Link harus diawali http:// atau https://', 'bad');
      return;
    }
    galleryFor(kind).push({
      id: 'i' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
      url: url,
      caption: capInput.value.trim()
    });
    urlInput.value = '';
    capInput.value = '';
    renderGallery(kind);
    save(true).then(function () { toast('Item ditambahkan.', 'ok'); }).catch(function () {});
  }

  function removeItem(kind, index) {
    galleryFor(kind).splice(index, 1);
    renderGallery(kind);
    save(true).then(function () { toast('Item dihapus.', 'ok'); }).catch(function () {});
  }

  function moveItem(kind, index, delta) {
    var items = galleryFor(kind);
    var target = index + delta;
    if (target < 0 || target >= items.length) return;
    var tmp = items[index];
    items[index] = items[target];
    items[target] = tmp;
    renderGallery(kind);
    save(true).catch(function () {});
  }

  /* ---------------------------------------------------------------- logo */

  function setupLogo() {
    $('logoFile').addEventListener('change', function (event) {
      var file = event.target.files && event.target.files[0];
      if (!file) return;
      if (file.size > 5 * 1024 * 1024) {
        toast('Ukuran file maksimal 5 MB.', 'bad');
        return;
      }
      var reader = new FileReader();
      reader.onload = function () {
        api('admin/logo', { method: 'POST', body: { dataUrl: reader.result } })
          .then(function (res) {
            $('lUrl').value = res.url;
            $('logoPreview').src = res.url + (res.url.indexOf('?') === -1 ? '?v=' + Date.now() : '');
            $('logoFile').value = '';
            toast('Logo diperbarui.', 'ok');
          })
          .catch(function (err) { toast('Gagal mengunggah logo: ' + err.message, 'bad'); });
      };
      reader.readAsDataURL(file);
    });

    $('logoResetBtn').addEventListener('click', function () {
      api('admin/logo', { method: 'POST', body: { reset: true } })
        .then(function (res) {
          $('lUrl').value = res.url;
          $('logoPreview').src = res.url + '?v=' + Date.now();
          toast('Logo dikembalikan ke bawaan.', 'ok');
        })
        .catch(function (err) { toast('Gagal: ' + err.message, 'bad'); });
    });

    $('lUrl').addEventListener('input', function () {
      $('logoPreview').src = $('lUrl').value || '/assets/logo.png';
    });
  }

  /* --------------------------------------------------------------- status */

  function formatDuration(seconds) {
    var s = Number(seconds) || 0;
    var d = Math.floor(s / 86400);
    var h = Math.floor((s % 86400) / 3600);
    var m = Math.floor((s % 3600) / 60);
    if (d) return d + ' hari ' + h + ' jam';
    if (h) return h + ' jam ' + m + ' menit';
    return m + ' menit';
  }

  function loadStatus() {
    api('admin/status').then(function (res) {
      state.status = res;
      var ddms = res.proxy || {};
      var ddmsState = 'Belum ada aktivitas';
      var ddmsTone = '';
      if (ddms.lastErrorAt && (!ddms.lastOkAt || ddms.lastErrorAt > ddms.lastOkAt)) {
        ddmsState = 'Terakhir gagal';
        ddmsTone = 'color:#fda4af';
      } else if (ddms.lastOkAt) {
        ddmsState = 'Aktif';
        ddmsTone = 'color:#86efac';
      }
      $('configPath').textContent = res.configPath;
      $('statGrid').innerHTML = [
        statCard('Versi panel', 'v' + res.version, 'Node ' + res.node),
        statCard('Server hidup', formatDuration(res.uptimeSeconds), 'uptime sistem ' + formatDuration(res.systemUptimeSeconds)),
        statCard('Memori panel', res.memory.rssMB + ' MB', 'RAM bebas ' + res.memory.freeMB + ' / ' + res.memory.totalMB + ' MB'),
        statCard('Koneksi DDMS', ddmsState, ddms.lastError ? ddms.lastError.slice(0, 70) : (ddms.lastStatus ? 'HTTP ' + ddms.lastStatus : 'host ' + res.hostname), ddmsTone)
      ].join('');
    }).catch(function (err) {
      $('statGrid').innerHTML = statCard('Gagal memuat status', err.message, '');
    });
  }

  function statCard(label, value, sub, style) {
    return '<div class="stat"><span class="k">' + escapeHtml(label) + '</span>' +
      '<strong style="' + (style || '') + '">' + escapeHtml(value) + '</strong>' +
      (sub ? '<small>' + escapeHtml(sub) + '</small>' : '') + '</div>';
  }

  function showResult(el, text, ok) {
    el.hidden = false;
    el.textContent = text;
    el.className = 'result ' + (ok ? 'ok' : 'bad');
  }

  function setupTests() {
    $('pingBtn').addEventListener('click', function () {
      var btn = this;
      btn.disabled = true;
      api('admin/ddms/ping', { method: 'POST' })
        .then(function (res) {
          showResult($('testResult'),
            (res.ok ? '✅ ' : '❌ ') + 'Target: ' + res.url + '\n' +
            'Status HTTP : ' + (res.status || '-') + '\n' +
            'Waktu       : ' + res.ms + ' ms' +
            (res.error ? '\nError       : ' + res.error : ''),
            res.ok);
        })
        .catch(function (err) { showResult($('testResult'), '❌ ' + err.message, false); })
        .finally(function () { btn.disabled = false; });
    });

    $('loginTestBtn').addEventListener('click', function () {
      var btn = this;
      btn.disabled = true;
      showResult($('testResult'), 'Mencoba login otomatis…', true);
      api('admin/ddms/test-login', { method: 'POST' })
        .then(function (res) {
          if (!res.ok && res.error) {
            showResult($('testResult'), '❌ ' + res.error, false);
            return;
          }
          var t = res.test || {};
          var lines = [(t.ok ? '✅ ' : '⚠️ ') + t.message];
          (t.steps || []).forEach(function (step, i) {
            lines.push('');
            lines.push((i + 1) + '. ' + step.step);
            Object.keys(step).forEach(function (key) {
              if (key === 'step') return;
              var value = step[key];
              if (value === null || value === undefined || value === '') return;
              lines.push('   - ' + key + ': ' + (typeof value === 'object' ? JSON.stringify(value) : value));
            });
          });
          showResult($('testResult'), lines.join('\n'), !!t.ok);
        })
        .catch(function (err) { showResult($('testResult'), '❌ ' + err.message, false); })
        .finally(function () { btn.disabled = false; });
    });

    $('reviewTestBtn').addEventListener('click', function () {
      var btn = this;
      btn.disabled = true;
      showResult($('reviewResult'), 'Mengambil ulasan…', true);
      api('admin/reviews/test', { method: 'POST' })
        .then(function (res) {
          if (!res.ok) {
            showResult($('reviewResult'), '❌ ' + res.error, false);
            return;
          }
          var d = res.data || {};
          if (d.mode === 'embed') {
            showResult($('reviewResult'), 'Mode embed aktif: ' + (d.embedUrl || '(URL kosong)'), true);
            return;
          }
          var lines = [
            '✅ Mode: ' + d.mode,
            'Tempat: ' + (d.name || '-'),
            'Rating: ' + (d.rating || '-') + ' (' + (d.total || 0) + ' ulasan)',
            'Jumlah ulasan diterima: ' + ((d.items || []).length),
            ''
          ];
          (d.items || []).slice(0, 3).forEach(function (item, i) {
            lines.push((i + 1) + ') ' + item.author + ' — ' + item.rating + '★ ' + (item.time || ''));
            lines.push('   "' + item.text.slice(0, 140) + '"');
          });
          showResult($('reviewResult'), lines.join('\n'), true);
        })
        .catch(function (err) { showResult($('reviewResult'), '❌ ' + err.message, false); })
        .finally(function () { btn.disabled = false; });
    });

    $('scriptPreviewBtn').addEventListener('click', function () {
      window.open('/__ahass/ulasan', '_blank', 'noopener');
    });

    $('reviewCacheBtn').addEventListener('click', function () {
      api('admin/reviews/clear-cache', { method: 'POST' })
        .then(function () { toast('Cache ulasan dikosongkan.', 'ok'); })
        .catch(function (err) { toast('Gagal: ' + err.message, 'bad'); });
    });
  }

  /* ------------------------------------------------------------ password */

  function setupPassword() {
    $('passwordBtn').addEventListener('click', function () {
      var current = $('secCurrent').value;
      var next = $('secNext').value;
      var confirm = $('secConfirm').value;
      if (next.length < 6) { toast('Password baru minimal 6 karakter.', 'bad'); return; }
      if (next !== confirm) { toast('Konfirmasi password tidak sama.', 'bad'); return; }
      var btn = this;
      btn.disabled = true;
      api('admin/password', { method: 'POST', body: { current: current, next: next } })
        .then(function () {
          toast('Password admin diubah.', 'ok');
          $('secCurrent').value = '';
          $('secNext').value = '';
          $('secConfirm').value = '';
        })
        .catch(function (err) { toast(err.message, 'bad'); })
        .finally(function () { btn.disabled = false; });
    });
  }

  /* ----------------------------------------------------------------- init */

  function bindStaticEvents() {
    $('saveBtn').addEventListener('click', function () { save(false); });
    $('logoutBtn').addEventListener('click', function () {
      api('admin/logout', { method: 'POST' }).then(showLogin).catch(showLogin);
    });
    $('rMode').addEventListener('change', function () {
      state.reviewMode = $('rMode').value || getSelect('rMode');
      updateModeFields();
    });
    $('dLeft').addEventListener('input', function () {
      $('leftValue').textContent = this.value + '%';
    });
    $('giAdd').addEventListener('click', function () { addItem('images'); });
    $('gvAdd').addEventListener('click', function () { addItem('videos'); });
    [$('giUrl'), $('gvUrl')].forEach(function (input) {
      input.addEventListener('keydown', function (e) {
        if (e.key === 'Enter') { e.preventDefault(); addItem(input === $('giUrl') ? 'images' : 'videos'); }
      });
    });

    $('loginForm').addEventListener('submit', function (event) {
      event.preventDefault();
      var btn = $('loginBtn');
      btn.disabled = true;
      setMsg($('loginMsg'), '');
      api('admin/login', { method: 'POST', body: { password: $('loginPassword').value } })
        .then(function () {
          $('loginPassword').value = '';
          showApp();
          loadConfig();
          loadStatus();
        })
        .catch(function (err) { setMsg($('loginMsg'), err.message); })
        .finally(function () { btn.disabled = false; });
    });

    document.addEventListener('keydown', function (event) {
      if ((event.ctrlKey || event.metaKey) && event.key === 's') {
        event.preventDefault();
        if (!$('appView').hidden) save(false);
      }
    });
  }

  function loadConfig() {
    return api('admin/config').then(function (cfg) {
      fillForm(cfg);
      return cfg;
    }).catch(function (err) {
      if ($('appView').hidden) return null;
      toast('Gagal memuat pengaturan: ' + err.message, 'bad');
      return null;
    });
  }

  function init() {
    bindStaticEvents();
    setupTabs();
    setupLogo();
    setupTests();
    setupPassword();

    api('admin/session')
      .then(function (res) {
        if (res.authed) {
          showApp();
          loadConfig();
          loadStatus();
        } else {
          showLogin();
        }
      })
      .catch(showLogin);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
}());
