/* Halaman admin Panel AHASS */
(function () {
  'use strict';

  var $ = function (id) { return document.getElementById(id); };

  var state = {
    fit: null,
    screen: null,
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

  /**
   * Jalankan setup satu per satu: kalau satu bagian gagal (mis. karena versi
   * HTML & JS tidak sinkron setelah update), tombol lain tetap hidup.
   * Sebelumnya satu error bisa membuat SEMUA tombol pas layar mati.
   */
  function safeSetup(name, fn) {
    try {
      fn();
    } catch (err) {
      if (window.console) console.error('[admin] gagal menyiapkan ' + name + ':', err);
      try { toast('Bagian "' + name + '" gagal dimuat: ' + err.message, 'bad'); } catch (_e) { /* diabaikan */ }
    }
  }

  /**
   * Pasang event listener dengan aman. Bila elemennya tidak ada (mis. HTML
   * lama dari cache browser), lewati saja - tombol lain tetap bekerja.
   */
  function on(target, event, handler) {
    var el = typeof target === 'string' ? $(target) : target;
    if (el && el.addEventListener) el.addEventListener(event, handler);
    return el;
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
    $('rJsonUrl').value = cfg.reviews.jsonUrl || '';
    $('uSvcDir').value = rs.dir || '';
    $('uSvcManage').checked = rs.manage !== false;
    $('uSvcPort').textContent = rs.port || 3000;
    $('rAvatar').checked = !!cfg.reviews.showAvatar;
    updateModeFields();

    // Display
    $('dLeft').value = cfg.display.leftPercent || 30;
    $('leftValue').textContent = ($('dLeft').value) + '%';
    var fit = readFit(cfg.display);
    state.fit = fit;
    syncFitInputs();
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

  /* ------------------------------------------------- pas layar (overscan) */

  function clampNum(value, min, max, fallback) {
    var n = Number(value);
    if (!isFinite(n)) return fallback;
    n = Math.round(n);
    return Math.max(min, Math.min(max, n));
  }

  function readFit(display) {
    var d = display || {};
    return {
      scalePercent: clampNum(d.scalePercent, 50, 100, 100),
      offsetX: clampNum(d.offsetX, -200, 200, 0),
      offsetY: clampNum(d.offsetY, -200, 200, 0),
      // tinggi panel kiri (persen). 100 = memenuhi tinggi layar seperti biasa.
      boxHeightPercent: clampNum(d.boxHeightPercent, 40, 100, 100),
      // sisi yang tetap: 'top' (bawah bergeser) atau 'bottom' (atas bergeser)
      boxAnchor: d.boxAnchor === 'bottom' ? 'bottom' : 'top',
      // skala & geser khusus layar DDMS (kanan)
      stageScalePercent: clampNum(d.stageScalePercent, 50, 150, 100),
      stageOffsetX: clampNum(d.stageOffsetX, -400, 400, 0),
      stageOffsetY: clampNum(d.stageOffsetY, -400, 400, 0)
    };
  }

  /** Hentikan pratinjau bila admin ditutup, lalu layar kembali normal. */
  function guardPreviewExit() {
    window.addEventListener('beforeunload', function () {
      // sendBeacon tidak bisa DELETE; cukup kirim sinyal lewat unload biasa
      // dengan fetch keepalive pada browser modern.
      try {
        fetch('/__ahass/api/admin/display/preview', {
          method: 'DELETE',
          credentials: 'same-origin',
          keepalive: true
        });
      } catch (_e) { /* abaikan */ }
    });
    document.addEventListener('visibilitychange', function () {
      if (document.hidden) stopPreview();
    });
  }

  /** Nilai slider lebar panel; aman bila elemennya belum ada. */
  function leftPercentValue(fallback) {
    var el = $('dLeft');
    var n = el ? Number(el.value) : 0;
    if (!isFinite(n) || n <= 0) {
      n = Number(fallback) || (state.cfg && state.cfg.display && state.cfg.display.leftPercent) || 30;
    }
    return n;
  }

  function setLeftPercent(value) {
    var el = $('dLeft');
    if (el) el.value = value;
    var label = $('leftValue');
    if (label) label.textContent = value + '%';
  }

  function syncFitInputs() {
    var fit = state.fit || readFit(null);
    $('scaleValue').textContent = fit.scalePercent + '%';
    var left = leftPercentValue();
    $('boxSizeValue').textContent = Math.round(left) + '% × ' + Math.round(fit.boxHeightPercent || 100) + '%';
    $('stageValue').textContent = Math.round(fit.stageScalePercent || 100) + '%';
    $('stageOffsetValue').textContent = (fit.stageOffsetX || 0) + ', ' + (fit.stageOffsetY || 0);
    $('offsetXValue').textContent = fit.offsetX;
    $('offsetYValue').textContent = fit.offsetY;
  }

  /**
   * Pratinjau langsung di tab ini (tanpa server): atur variabel CSS yang
   * dipakai .shell di public/style.css.
   */
  var previewTimer = null;
  var previewPending = false;

  /** Kirim nilai sekarang ke layar kiosk (maks ~6x per detik). */
  function pushPreview(immediate) {
    var fit = state.fit || readFit(null);
    // Slider bisa belum terisi (fillForm belum jalan) — jangan kirim 0, karena
    // server akan menjepitnya ke 20% dan panel kiri tiba-tiba menyempit.
    var left = leftPercentValue();
    var payload = {
      display: {
        leftPercent: left,
        boxHeightPercent: fit.boxHeightPercent,
        boxAnchor: fit.boxAnchor,
        stageScalePercent: fit.stageScalePercent || 100,
        stageOffsetX: fit.stageOffsetX || 0,
        stageOffsetY: fit.stageOffsetY || 0,
        scalePercent: fit.scalePercent,
        offsetX: fit.offsetX,
        offsetY: fit.offsetY
      }
    };

    var send = function () {
      previewPending = false;
      // Ambil nilai TERBARU saat dikirim (state.fit bisa berubah setelah
      // antrean throttle) supaya layar mengikuti posisi terakhir.
      var now = state.fit || readFit(null);
      payload.display.boxHeightPercent = now.boxHeightPercent;
      payload.display.boxAnchor = now.boxAnchor;
      payload.display.stageScalePercent = now.stageScalePercent || 100;
      payload.display.stageOffsetX = now.stageOffsetX || 0;
      payload.display.stageOffsetY = now.stageOffsetY || 0;
      payload.display.scalePercent = now.scalePercent;
      payload.display.offsetX = now.offsetX;
      payload.display.offsetY = now.offsetY;
      payload.display.leftPercent = leftPercentValue();
      api('admin/display/preview', { method: 'POST', body: payload })
        .then(function (res) {
          if (res && res.clients !== undefined) setScreenLink(res.clients);
        })
        .catch(function () {
          /* pratinjau bersifat opsional; jangan ganggu pengguna */
        });
    };

    if (immediate) {
      if (previewTimer) { clearTimeout(previewTimer); previewTimer = null; }
      send();
      return;
    }
    if (previewTimer) { previewPending = true; return; }
    send();
    previewTimer = setTimeout(function () {
      previewTimer = null;
      if (previewPending) pushPreview(false);
    }, 160);
  }

  /** Tampilkan status: apakah layar kiosk tersambung (menerima perintah)? */
  function setScreenLink(clients) {
    var el = $('screenLinkState');
    if (!el) return;
    var n = Number(clients);
    if (!isFinite(n)) return;
    if (n > 0) {
      el.textContent = 'terhubung (' + n + ') — tombol langsung menggerakkan layar';
      el.style.color = '#86efac';
    } else {
      el.textContent = 'tidak terhubung — jalankan: sudo systemctl restart ahass-kiosk';
      el.style.color = '#fda4af';
    }
  }

  function refreshScreenLink() {
    return api('health')
      .then(function (res) { setScreenLink(res.screens); })
      .catch(function () { /* diamkan */ });
  }

  /** Kembalikan layar ke nilai yang tersimpan. */
  function stopPreview() {
    if (previewTimer) { clearTimeout(previewTimer); previewTimer = null; }
    previewPending = false;
    api('admin/display/preview', { method: 'DELETE' }).catch(function () {});
  }

  function previewFit() {
    var fit = state.fit;
    var root = document.documentElement.style;
    root.setProperty('--panel-h', (fit.boxHeightPercent || 100) + '%');
    root.setProperty('--panel-anchor', fit.boxAnchor === 'bottom' ? 'end' : 'start');
    root.setProperty('--stage-scale', String((fit.stageScalePercent || 100) / 100));
    root.setProperty('--stage-x', (fit.stageOffsetX || 0) + 'px');
    root.setProperty('--stage-y', (fit.stageOffsetY || 0) + 'px');
    root.setProperty('--screen-scale', String(fit.scalePercent / 100));
    root.setProperty('--screen-x', fit.offsetX + 'px');
    root.setProperty('--screen-y', fit.offsetY + 'px');
  }

  /**
   * Ubah skala layar dalam langkah 2%. Sesuai permintaan di lapangan:
   * ◀ / ▲ memperbesar, ▶ / ▼ memperkecil (semua tombol berlaku sama).
   */
  function zoomFit(delta) {
    var fit = state.fit || readFit(null);
    state.fit = {
      scalePercent: clampNum(fit.scalePercent + delta, 50, 100, 100),
      offsetX: fit.offsetX,
      offsetY: fit.offsetY,
      boxHeightPercent: fit.boxHeightPercent,
      boxAnchor: fit.boxAnchor,
      stageScalePercent: fit.stageScalePercent,
      stageOffsetX: fit.stageOffsetX,
      stageOffsetY: fit.stageOffsetY
    };
    syncFitInputs();
    previewFit();
  }

  /**
   * Tombol per sisi: mengubah sisi panel kiri / DDMS.
   *
   *  left-in / left-out    -> lebar panel kiri (kiri mepet ke kanan / ke kiri)
   *  right-in / right-out  -> lebar DDMS  (kanan mepet ke kiri / ke kanan)
   *  top-in / top-out      -> tinggi panel kiri, sisi atas mepet atas / bawah
   *  bottom-in / bottom-out-> tinggi panel kiri, sisi bawah mepet bawah / atas
   *
   * "in" = sisi itu masuk/membesar, "out" = sisi itu keluar/mengecil.
   */
  function adjustEdge(action) {
    var fit = state.fit || readFit(null);
    var left = clampNum(leftPercentValue(), 20, 60, 30);
    var height = clampNum(fit.boxHeightPercent, 40, 100, 100);
    var step = 1;   // 1% per klik

    var before = { left: left, height: height };

    if (action === 'left-in') left = clampNum(left + step, 20, 60, 30);
    else if (action === 'left-out') left = clampNum(left - step, 20, 60, 30);
    else if (action === 'right-in') left = clampNum(left - step, 20, 60, 30);
    else if (action === 'right-out') left = clampNum(left + step, 20, 60, 30);
    else if (action === 'top-in' || action === 'bottom-in') height = clampNum(height + step, 40, 100, 100);
    else if (action === 'top-out' || action === 'bottom-out') height = clampNum(height - step, 40, 100, 100);

    // Sisi atas yang bergeser -> panel menempel di bawah; sebaliknya menempel di atas.
    var anchor = fit.boxAnchor;
    if (action.indexOf('top-') === 0) anchor = 'bottom';
    else if (action.indexOf('bottom-') === 0) anchor = 'top';

    setLeftPercent(left);
    state.fit = {
      scalePercent: fit.scalePercent,
      offsetX: fit.offsetX,
      offsetY: fit.offsetY,
      boxHeightPercent: height,
      boxAnchor: anchor
    };
    syncFitInputs();
    previewFit();

    // Beri tahu kalau sudah di batas, supaya tombol tidak terasa "tidak jalan".
    if (before.left === left && before.height === height) {
      var limit = action.indexOf('in') > -1 ? 'maksimum' : 'minimum';
      toast('Sudah di batas ' + limit + ' (' + left + '% / ' + height + '%).', 'ok');
    }
  }

  /**
   * Layar DDMS (kanan): skala dan geser sendiri. Berguna saat bagian atas DDMS
   * (menu/header) terpotong: perkecil dengan ▶ lalu geser ke atas dengan ▲.
   */
  function adjustStage(action) {
    var fit = state.fit || readFit(null);
    var scale = clampNum(fit.stageScalePercent, 50, 150, 100);
    var x = clampNum(fit.stageOffsetX, -400, 400, 0);
    var y = clampNum(fit.stageOffsetY, -400, 400, 0);
    var before = { s: scale, x: x, y: y };

    if (action === 'in') scale = clampNum(scale + 2, 50, 150, 100);
    else if (action === 'out') scale = clampNum(scale - 2, 50, 150, 100);
    else if (action === 'up') y = clampNum(y - 8, -400, 400, 0);
    else if (action === 'down') y = clampNum(y + 8, -400, 400, 0);
    else if (action === 'left') x = clampNum(x - 8, -400, 400, 0);
    else if (action === 'right') x = clampNum(x + 8, -400, 400, 0);

    state.fit = {
      scalePercent: fit.scalePercent,
      offsetX: fit.offsetX,
      offsetY: fit.offsetY,
      boxHeightPercent: fit.boxHeightPercent,
      boxAnchor: fit.boxAnchor,
      stageScalePercent: scale,
      stageOffsetX: x,
      stageOffsetY: y
    };
    syncFitInputs();
    previewFit();

    if (before.s === scale && before.x === x && before.y === y) {
      toast('Sudah di batas (' + scale + '%).', 'ok');
    }
  }

  function moveFit(dx, dy) {
    var fit = state.fit || readFit(null);
    if (dx === 0 && dy === 0) {
      // ◎ = mulai ulang: geser 0,0 dan skala 100% (tinggi panel tetap)
      state.fit = { scalePercent: 100, offsetX: 0, offsetY: 0,
        boxHeightPercent: fit.boxHeightPercent, boxAnchor: fit.boxAnchor,
        stageScalePercent: fit.stageScalePercent, stageOffsetX: fit.stageOffsetX,
        stageOffsetY: fit.stageOffsetY };
    } else {
      state.fit = {
        scalePercent: fit.scalePercent,
        offsetX: clampNum(fit.offsetX + dx, -200, 200, 0),
        offsetY: clampNum(fit.offsetY + dy, -200, 200, 0),
        boxHeightPercent: fit.boxHeightPercent,
        boxAnchor: fit.boxAnchor,
        stageScalePercent: fit.stageScalePercent,
        stageOffsetX: fit.stageOffsetX,
        stageOffsetY: fit.stageOffsetY
      };
    }
    syncFitInputs();
    previewFit();
  }

  /* ------------------------------------------------ resolusi layar kiosk */

  function loadScreenInfo() {
    var mode = $('resMode');
    var current = $('resCurrent');
    var hint = $('resHint');
    if (!mode || !current) return;

    api('admin/system/screen').then(function (info) {
      state.screen = info;
      if (!info || !info.supported) {
        current.value = 'tidak didukung di perangkat ini';
        hint.textContent = 'Ubah resolusi manual lewat dietpi-config (Display Options → Display Resolution).';
        $('resApplyBtn').disabled = true;
        return;
      }
      current.value = (info.current || 'tidak diketahui') +
        (info.source ? '  (' + info.source + ')' : '');
      $('resOverscan').checked = !!info.overscanDisabled;

      var matches = (info.modes || []).filter(function (m) { return m.mode === info.hdmiMode; });
      var selected = matches.length ? matches[0].size : '';
      if (selected) setSelect('resMode', selected);
      hint.textContent = info.hdmiMode
        ? 'Terbaca dari /boot/firmware/config.txt: mode ' + info.hdmiMode + '.'
        : 'Belum ada hdmi_mode khusus; DietPi memakai mode otomatis (EDID TV).';
    }).catch(function (err) {
      current.value = 'gagal dibaca';
      hint.textContent = 'Tidak bisa membaca setelan layar: ' + err.message;
    });
  }

  function applyResolution() {
    var size = getSelect('resMode');
    var overscan = $('resOverscan').checked;
    if (!size && !overscan) {
      toast('Pilih resolusi dulu (atau centang matikan overscan).', 'bad');
      return;
    }

    var body = { overscan: overscan };
    if (size) {
      var parts = String(size).split('x');
      body.width = Number(parts[0]);
      body.height = Number(parts[1]);
    }

    var label = size || 'overscan';
    if (!window.confirm('Terapkan ' + label + ' lalu perangkat akan reboot. Layar akan mati beberapa saat. Lanjut?')) {
      return;
    }

    var btn = $('resApplyBtn');
    btn.disabled = true;
    api('admin/system/resolution', { method: 'POST', body: body })
      .then(function (res) {
        toast(res.message || 'Resolusi diterapkan. Perangkat reboot…', 'ok');
        $('resHint').textContent = 'Menunggu reboot… layar akan menyala kembali otomatis.';
      })
      .catch(function (err) {
        btn.disabled = false;
        toast('Gagal menerapkan resolusi: ' + err.message, 'bad');
      });
  }

  function collect() {
    return {
      display: {
        leftPercent: clampNum(leftPercentValue(), 20, 60, 30),
        boxHeightPercent: (state.fit && state.fit.boxHeightPercent) || 100,
        boxAnchor: (state.fit && state.fit.boxAnchor) || 'top',
        stageScalePercent: (state.fit && state.fit.stageScalePercent) || 100,
        stageOffsetX: (state.fit && state.fit.stageOffsetX) || 0,
        stageOffsetY: (state.fit && state.fit.stageOffsetY) || 0,
        scalePercent: state.fit ? state.fit.scalePercent : 100,
        offsetX: state.fit ? state.fit.offsetX : 0,
        offsetY: state.fit ? state.fit.offsetY : 0,
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
        jsonUrl: $('rJsonUrl').value.trim(),
        showAvatar: $('rAvatar').checked,
        script: {
          code: $('rScriptCode').value,
          host: $('rScriptHost').value.trim(),
          port: Number($('rScriptPort').value) || 3000,
          path: $('rScriptPath').value.trim() || '/loader.js',
          query: $('rScriptQuery').value.trim(),
          manage: $('uSvcManage').checked,
          dir: $('uSvcDir').value.trim()
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
    on('logoFile', 'change', function (event) {
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

    on('logoResetBtn', 'click', function () {
      api('admin/logo', { method: 'POST', body: { reset: true } })
        .then(function (res) {
          $('lUrl').value = res.url;
          $('logoPreview').src = res.url + '?v=' + Date.now();
          toast('Logo dikembalikan ke bawaan.', 'ok');
        })
        .catch(function (err) { toast('Gagal: ' + err.message, 'bad'); });
    });

    on('lUrl', 'input', function () {
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
    on('pingBtn', 'click', function () {
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

    on('loginTestBtn', 'click', function () {
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

    on('reviewTestBtn', 'click', function () {
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

    on('scriptPreviewBtn', 'click', function () {
      window.open('/__ahass/ulasan', '_blank', 'noopener');
    });

    on('reviewCacheBtn', 'click', function () {
      api('admin/reviews/clear-cache', { method: 'POST' })
        .then(function () { toast('Cache ulasan dikosongkan.', 'ok'); })
        .catch(function (err) { toast('Gagal: ' + err.message, 'bad'); });
    });
  }

  /* ------------------------------------------- layanan ulasan-google (3000) */

  function refreshUlasanStatus() {
    return api('admin/ulasan/status')
      .then(function (res) { renderUlasanStatus(res.status); })
      .catch(function (err) {
        if ($('uSvcState')) $('uSvcState').textContent = 'tidak bisa memeriksa';
        if ($('uSvcDetail')) $('uSvcDetail').textContent = err.message;
      });
  }

  function renderUlasanStatus(st) {
    if (!st) return;
    var dot = $('uSvcDot');
    var state = st.running ? 'Berjalan' : 'Berhenti';
    if (st.http && st.http.up) state += ' — port ' + st.port + ' menjawab';
    $('uSvcState').textContent = state;
    dot.className = 'dot ' + (st.running ? 'ok' : 'bad');
    $('uSvcPort').textContent = st.port;

    var bits = [];
    bits.push(st.dir ? 'folder: ' + st.dir : 'folder belum ditemukan');
    if (st.systemd && st.systemd.installed) {
      bits.push('autostart: ' + (st.systemd.active ? 'aktif' : 'terpasang, belum aktif'));
    } else {
      bits.push('autostart: belum dipasang');
    }
    if (st.managedProcess) bits.push('dijalankan oleh panel');
    if (st.builtin && st.builtin.active) {
      bits.push('widget bawaan aktif di port ' + st.builtin.port + (st.builtinSource === 'json' ? ' (URL JSON)' : ''));
    } else if (st.builtin && st.builtin.error) {
      bits.push('widget bawaan: ' + st.builtin.error);
    }
    if (st.error) bits.push(st.error);
    $('uSvcDetail').textContent = bits.join(' · ');
    if (!$('uSvcDir').value && st.dir) $('uSvcDir').placeholder = st.dir;
    $('uSvcStop').disabled = !st.managedProcess;
  }

  function ulasanAction(action, button) {
    var label = button ? button.textContent : '';
    if (button) { button.disabled = true; button.textContent = 'memproses…'; }
    var opts = { method: 'POST' };
    if (action === 'start') opts.body = JSON.stringify({ dir: $('uSvcDir').value.trim() });
    return api('admin/ulasan/' + action, opts)
      .then(function (res) {
        if (res.status) renderUlasanStatus(res.status);
        toast(res.message || (res.ok ? 'Selesai.' : 'Gagal.'), res.ok ? 'ok' : 'bad');
      })
      .catch(function (err) { toast('Gagal: ' + err.message, 'bad'); })
      .finally(function () {
        if (button) { button.disabled = false; button.textContent = label; }
      });
  }

  function setupUlasanService() {
    on('uSvcStart', 'click', function () { ulasanAction('start', this); });
    on('uSvcStop', 'click', function () { ulasanAction('stop', this); });
    on('uSvcInstall', 'click', function () { ulasanAction('install', this); });
    on('uSvcRefresh', 'click', function () { refreshUlasanStatus(); });
    on('uSvcTest', 'click', function () {
      var btn = this;
      btn.disabled = true;
      btn.textContent = 'mengambil…';
      api('admin/reviews/test', { method: 'POST' })
        .then(function (res) {
          if (!res.ok) throw new Error(res.error || 'Gagal');
          var d = res.data || {};
          var n = (d.items || []).length;
          var who = (d.items && d.items[0] && d.items[0].author) || '-';
          toast('Ulasan terbaca: ' + n + ' item' + (d.rating ? ', rating ' + d.rating : '') +
            (n ? ' (contoh: ' + who + ')' : ''), 'ok');
        })
        .catch(function (err) { toast('Gagal: ' + err.message, 'bad'); })
        .finally(function () { btn.disabled = false; btn.textContent = 'Uji ambil ulasan sekarang'; });
    });
    on('rScriptPort', 'change', function () { $('uSvcPort').textContent = this.value || 3000; });
  }

  /* ------------------------------------------------------------ password */

  function setupPassword() {
    on('passwordBtn', 'click', function () {
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
    on('saveBtn', 'click', function () { save(false); });
    on('logoutBtn', 'click', function () {
      api('admin/logout', { method: 'POST' }).then(showLogin).catch(showLogin);
    });
    on('rMode', 'change', function () {
      state.reviewMode = $('rMode').value || getSelect('rMode');
      updateModeFields();
    });
    on('dLeft', 'input', function () {
      var label = $('leftValue');
      if (label) label.textContent = this.value + '%';
      pushPreview(false);
    });
    on('dLeft', 'change', function () { pushPreview(true); });

    // Pas layar: dua kelompok tombol (geser & ukur), semuanya realtime
    Array.prototype.forEach.call(document.querySelectorAll('[data-stage]'), function (btn) {
      btn.addEventListener('click', function () {
        adjustStage(btn.getAttribute('data-stage'));
        pushPreview(false);
      });
    });

    // Simpan pas layar = simpan SEMUA perubahan (panel kiri + DDMS + skala/geser).
    on('fitSaveBtn', 'click', function () {
      save(false).then(function () {
        stopPreview();
      }).catch(function () { /* pesan sudah ditampilkan save() */ });
    });
    on('fitCancelBtn', 'click', function () {
      stopPreview();
      toast('Pratinjau dibatalkan, layar kembali ke setelan tersimpan.', 'ok');
    });

    Array.prototype.forEach.call(document.querySelectorAll('[data-zoom]'), function (btn) {
      btn.addEventListener('click', function () {
        var step = 2;   // 2% per klik
        switch (btn.getAttribute('data-zoom')) {
          case 'in': case 'in-y': zoomFit(step); break;
          case 'out': case 'out-y': zoomFit(-step); break;
          default: zoomFit(100 - (state.fit || readFit(null)).scalePercent); break;  // reset 100%
        }
        pushPreview(false);
      });
    });

    Array.prototype.forEach.call(document.querySelectorAll('[data-edge]'), function (btn) {
      btn.addEventListener('click', function () {
        adjustEdge(btn.getAttribute('data-edge'));
        pushPreview(false);
      });
    });

    on('fitResetBtn', 'click', function () {
      var fit = state.fit || readFit(null);
      state.fit = { scalePercent: 100, offsetX: 0, offsetY: 0, boxHeightPercent: 100,
        boxAnchor: 'top', stageScalePercent: 100, stageOffsetX: 0, stageOffsetY: 0 };
      setLeftPercent(30);
      syncFitInputs();
      previewFit();
      pushPreview(true);
      toast('Ukuran & geser dikembalikan ke normal (30% / 100%).', 'ok');
    });

    Array.prototype.forEach.call(document.querySelectorAll('[data-move]'), function (btn) {
      btn.addEventListener('click', function () {
        switch (btn.getAttribute('data-move')) {
          case 'up': moveFit(0, -4); break;
          case 'down': moveFit(0, 4); break;
          case 'left': moveFit(-4, 0); break;
          case 'right': moveFit(4, 0); break;
          default: moveFit(0, 0); break;   // reset
        }
        pushPreview(false);
      });
    });

    // Resolusi layar
    on('resApplyBtn', 'click', applyResolution);
    loadScreenInfo();
    guardPreviewExit();
    refreshScreenLink();
    on('giAdd', 'click', function () { addItem('images'); });
    on('gvAdd', 'click', function () { addItem('videos'); });
    [$('giUrl'), $('gvUrl')].forEach(function (input) {
      input.addEventListener('keydown', function (e) {
        if (e.key === 'Enter') { e.preventDefault(); addItem(input === $('giUrl') ? 'images' : 'videos'); }
      });
    });

    on('loginForm', 'submit', function (event) {
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
          refreshUlasanStatus();
          refreshScreenLink();
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
    safeSetup('tata letak & tombol', bindStaticEvents);
    safeSetup('tab', setupTabs);
    safeSetup('logo', setupLogo);
    safeSetup('pengujian', setupTests);
    safeSetup('layanan ulasan', setupUlasanService);
    safeSetup('password', setupPassword);

    api('admin/session')
      .then(function (res) {
        if (res.authed) {
          showApp();
          loadConfig();
          loadStatus();
          refreshUlasanStatus();
        } else {
          showLogin();
        }
      })
      .catch(showLogin);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
}());
