/* Panel display AHASS — tanpa framework, hemat CPU untuk Intel Compute Stick */
(function () {
  'use strict';

  var $ = function (id) { return document.getElementById(id); };

  var state = {
    cfg: null,
    signature: '',
    reviews: null,
    reviewIndex: 0,
    imageIndex: 0,
    videoIndex: 0,
    timers: {},
    frameLoadedAt: 0
  };

  /* ---------------------------------------------------------------- util */

  function stars(rating) {
    var n = Math.max(0, Math.min(5, Math.round(Number(rating) || 0)));
    var out = '';
    for (var i = 0; i < 5; i += 1) out += i < n ? '★' : '☆';
    return out;
  }

  function pad(n) { return n < 10 ? '0' + n : '' + n; }

  function isInstanceHidden() {
    return document.visibilityState === 'hidden';
  }

  function setTimer(name, fn, ms) {
    clearTimer(name);
    if (!ms || ms <= 0) return;
    state.timers[name] = setInterval(function () {
      if (isInstanceHidden()) return;
      fn();
    }, ms);
  }

  function clearTimer(name) {
    if (state.timers[name]) {
      clearInterval(state.timers[name]);
      delete state.timers[name];
    }
  }

  function escapeHtml(text) {
    return String(text == null ? '' : text)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  /* ------------------------------------------------ deteksi embed sosmed */

  function embedFor(rawUrl) {
    var url;
    try {
      url = new URL(String(rawUrl), location.href);
    } catch (_err) {
      return null;
    }
    var host = url.hostname.replace(/^www\./, '').replace(/^m\./, '');
    var pathname = url.pathname;

    // YouTube
    if (/(^|\.)youtube\.com$/.test(host) || host === 'youtu.be' || host === 'youtube-nocookie.com') {
      var vid = '';
      if (host === 'youtu.be') vid = pathname.slice(1);
      else if (url.searchParams.get('v')) vid = url.searchParams.get('v');
      else {
        var m = pathname.match(/\/(embed|shorts|live|v)\/([\w-]{6,20})/);
        if (m) vid = m[2];
      }
      if (vid) {
        return {
          type: 'iframe',
          url: 'https://www.youtube-nocookie.com/embed/' + encodeURIComponent(vid) +
            '?autoplay=1&mute=1&loop=1&playlist=' + encodeURIComponent(vid) +
            '&playsinline=1&rel=0&modestbranding=1&iv_load_policy=3&disablekb=1'
        };
      }
      return null;
    }

    // Instagram (post/reel) -> embed resmi
    if (/(^|\.)instagram\.com$/.test(host)) {
      var ig = pathname.match(/\/(p|reel|reels|tv)\/([\w-]+)/);
      if (ig) {
        var kind = ig[1] === 'reels' ? 'reel' : ig[1];
        return { type: 'iframe', url: 'https://www.instagram.com/' + kind + '/' + ig[2] + '/embed/captioned/' };
      }
      return null;
    }

    // Facebook video / post
    if (/(^|\.)facebook\.com$/.test(host) || host === 'fb.watch') {
      var isVideo = /\/videos?\//.test(pathname) || /\/reel\//.test(pathname) || host === 'fb.watch';
      if (isVideo) {
        return {
          type: 'iframe',
          url: 'https://www.facebook.com/plugins/video.php?href=' + encodeURIComponent(url.href) +
            '&show_text=false&autoplay=1&mute=1&width=640'
        };
      }
      return {
        type: 'iframe',
        url: 'https://www.facebook.com/plugins/post.php?href=' + encodeURIComponent(url.href) +
          '&show_text=true&width=500'
      };
    }

    // TikTok
    if (/(^|\.)tiktok\.com$/.test(host)) {
      var tk = pathname.match(/\/video\/(\d+)/);
      if (tk) {
        return { type: 'iframe', url: 'https://www.tiktok.com/player/v1/' + tk[1] + '?autoplay=1&muted=1&loop=1&controls=0' };
      }
      return null;
    }

    // Vimeo
    if (/(^|\.)vimeo\.com$/.test(host)) {
      var vm = pathname.match(/(\d{6,})/);
      if (vm) return { type: 'iframe', url: 'https://player.vimeo.com/video/' + vm[1] + '?autoplay=1&muted=1&loop=1&background=1' };
      return null;
    }

    // Google Drive
    if (host === 'drive.google.com') {
      var gd = pathname.match(/\/d\/([\w-]+)/);
      if (gd) return { type: 'iframe', url: 'https://drive.google.com/file/d/' + gd[1] + '/preview' };
      return null;
    }

    // File video langsung
    if (/\.(mp4|webm|ogv|ogg|m4v)(\?.*)?$/i.test(pathname + url.search)) {
      return { type: 'video', url: url.href };
    }

    // Gambar langsung
    if (/\.(png|jpe?g|webp|gif|avif|svg)(\?.*)?$/i.test(pathname + url.search)) {
      return { type: 'image', url: url.href };
    }

    return null;
  }

  /* --------------------------------------------------------------- clock */

  var DAYS = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];
  var MONTHS = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli',
    'Agustus', 'September', 'Oktober', 'November', 'Desember'];

  function tickClock() {
    var now = new Date();
    var use24 = !state.cfg || state.cfg.display.clock24 !== false;
    var showSeconds = !state.cfg || state.cfg.display.showSeconds !== false;
    var hours = now.getHours();
    var suffix = '';
    if (!use24) {
      suffix = hours >= 12 ? ' PM' : ' AM';
      hours = hours % 12 || 12;
    }
    $('clockTime').firstChild.nodeValue = pad(hours) + ':' + pad(now.getMinutes());
    $('clockSecs').textContent = showSeconds ? ':' + pad(now.getSeconds()) + suffix : suffix;
    $('clockDate').textContent =
      DAYS[now.getDay()] + ', ' + now.getDate() + ' ' + MONTHS[now.getMonth()] + ' ' + now.getFullYear();
  }

  /* -------------------------------------------------------------- status */

  function setStatus(kind, text) {
    var pill = $('statusPill');
    pill.className = 'status-pill' + (kind ? ' is-' + kind : '');
    pill.lastElementChild.textContent = text;
  }

  function checkHealth() {
    fetch('/__ahass/api/health', { cache: 'no-store' })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        if (!data || !data.ok) return;
        var ddms = data.ddms || {};
        var now = Date.now();
        if (ddms.lastOkAt && now - ddms.lastOkAt < 5 * 60 * 1000) {
          if (!ddms.lastErrorAt || ddms.lastOkAt > ddms.lastErrorAt) {
            setStatus('ok', 'DDMS terhubung');
            return;
          }
        }
        if (ddms.lastErrorAt && (!ddms.lastOkAt || ddms.lastErrorAt > ddms.lastOkAt)) {
          setStatus('err', 'DDMS terputus');
          return;
        }
        setStatus('', 'DDMS menunggu');
      })
      .catch(function () { setStatus('warn', 'Server lokal offline'); });
  }

  /* -------------------------------------------------------------- ulasan */

  function renderReviewEmbed(url) {
    var body = $('reviewBody');
    body.innerHTML = '';
    var stage = document.createElement('div');
    stage.className = 'media-stage';
    stage.style.position = 'relative';
    stage.style.flex = '1 1 auto';
    var frame = document.createElement('iframe');
    frame.src = url;
    frame.loading = 'lazy';
    frame.style.position = 'absolute';
    frame.style.inset = '0';
    frame.style.width = '100%';
    frame.style.height = '100%';
    frame.style.border = '0';
    frame.style.background = '#fff';
    stage.appendChild(frame);
    body.appendChild(stage);
    $('ratingSummary').style.display = 'none';
    $('reviewCta').hidden = true;
  }

  function renderReviews(data) {
    var body = $('reviewBody');
    body.innerHTML = '';
    state.reviewIndex = 0;

    if (!data || data.ok === false) {
      body.innerHTML = '<div class="review-empty">' + escapeHtml((data && data.error) || 'Ulasan belum tersedia.') + '</div>';
      $('ratingSummary').style.display = 'none';
      return;
    }
    if (data.mode === 'embed') {
      if (data.embedUrl) renderReviewEmbed(data.embedUrl);
      else body.innerHTML = '<div class="review-empty">URL embed ulasan belum diisi.</div>';
      return;
    }

    var items = data.items || [];
    var rating = Number(data.rating) || 0;
    var total = Number(data.total) || 0;

    if (!items.length) {
      body.innerHTML = '<div class="review-empty">Belum ada ulasan yang bisa ditampilkan.' +
        (data.error ? '<br><small>' + escapeHtml(data.error) + '</small>' : '') + '</div>';
      $('ratingSummary').style.display = 'none';
    } else {
      $('ratingSummary').style.display = '';
      $('ratingValue').textContent = rating ? rating.toFixed(1) : '–';
      $('ratingStars').textContent = stars(rating);
      $('ratingCount').textContent = total ? '(' + total + ' ulasan)' : '';

      items.forEach(function (item, index) {
        var card = document.createElement('div');
        card.className = 'review-card' + (index === 0 ? ' is-active' : '');
        var avatar = '';
        if (state.cfg && state.cfg.reviews.showAvatar && item.avatar) {
          avatar = '<img src="' + escapeHtml(item.avatar) + '" alt="" loading="lazy" referrerpolicy="no-referrer">';
        }
        card.innerHTML =
          '<div class="review-stars">' + stars(item.rating) + '</div>' +
          '<div class="review-text">“' + escapeHtml(item.text) + '”</div>' +
          '<div class="review-who">' + avatar +
          '<span class="who-name">' + escapeHtml(item.author) + '</span>' +
          (item.time ? '<span class="who-time">· ' + escapeHtml(item.time) + '</span>' : '') +
          '</div>';
        body.appendChild(card);
      });
    }

    var cta = $('reviewCta');
    if (data.url) {
      cta.href = data.url;
      cta.hidden = false;
    } else {
      cta.hidden = true;
    }

    var rotate = (state.cfg ? state.cfg.display.rotateSeconds : 12) * 1000;
    setTimer('reviews', function () {
      var cards = body.querySelectorAll('.review-card');
      if (cards.length < 2) return;
      cards[state.reviewIndex].classList.remove('is-active');
      state.reviewIndex = (state.reviewIndex + 1) % cards.length;
      cards[state.reviewIndex].classList.add('is-active');
    }, rotate);
  }

  function loadReviews(force) {
    var cfg = state.cfg;
    if (!cfg) return;
    if (cfg.reviews.mode === 'off') {
      $('reviewBody').innerHTML = '<div class="review-empty">Widget ulasan Google belum diaktifkan.<br><small>Atur di halaman admin → Ulasan Google.</small></div>';
      $('ratingSummary').style.display = 'none';
      $('reviewCta').hidden = true;
      clearTimer('reviews');
      return;
    }
    if (cfg.reviews.mode === 'embed') {
      renderReviews({ ok: true, mode: 'embed', embedUrl: cfg.reviews.embedUrl });
      clearTimer('reviews');
      return;
    }
    fetch('/__ahass/api/reviews' + (force ? '?force=1' : ''), { cache: 'no-store' })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        state.reviews = data;
        renderReviews(data);
      })
      .catch(function (err) {
        renderReviews({ ok: false, error: 'Gagal memuat ulasan: ' + err.message });
      });
    // refresh tiap 30 menit (server juga punya cache sendiri)
    setTimer('reviewsRefresh', function () { loadReviews(false); }, 30 * 60 * 1000);
  }

  /* ------------------------------------------------------- kotak 4: foto */

  function clearEmbeds(container) {
    var nodes = container.querySelectorAll('iframe.video-frame');
    for (var i = 0; i < nodes.length; i += 1) {
      nodes[i].parentNode.removeChild(nodes[i]);
    }
  }

  function buildDots(container, count, activeIndex) {
    if (!container) return;
    container.innerHTML = '';
    if (count < 2) return;
    for (var i = 0; i < count; i += 1) {
      var dot = document.createElement('span');
      if (i === activeIndex) dot.className = 'on';
      container.appendChild(dot);
    }
  }

  function showSlide(index) {
    var cfg = state.cfg;
    var items = (cfg.gallery.images || []);
    var stage = $('imageStage');
    var img = $('imgA');
    var empty = $('imageEmpty');
    var caption = $('imageCaption');

    if (!items.length) {
      clearEmbeds(stage);
      img.classList.remove('is-active');
      empty.hidden = false;
      caption.textContent = '';
      buildDots($('imageDots'), 0, 0);
      return;
    }

    empty.hidden = true;
    state.imageIndex = ((index % items.length) + items.length) % items.length;
    var item = items[state.imageIndex];
    var embed = embedFor(item.url);
    caption.textContent = item.caption || '';
    buildDots($('imageDots'), items.length, state.imageIndex);

    if (embed && embed.type === 'iframe') {
      clearEmbeds(stage);
      img.classList.remove('is-active');
      var frame = document.createElement('iframe');
      frame.className = 'video-frame';
      frame.src = embed.url;
      frame.loading = 'lazy';
      frame.allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen';
      frame.setAttribute('scrolling', 'no');
      stage.insertBefore(frame, caption);
      return;
    }

    clearEmbeds(stage);
    img.onload = function () { img.classList.add('is-active'); };
    img.onerror = function () {
      img.classList.remove('is-active');
      empty.hidden = false;
      empty.innerHTML = 'Gambar gagal dimuat.<br><small>' + escapeHtml(item.url) + '</small>';
    };
    img.src = (embed && embed.url) || item.url;
    if (img.complete) img.classList.add('is-active');
  }

  function startImageRotation() {
    var cfg = state.cfg;
    var count = (cfg.gallery.images || []).length;
    showSlide(0);
    if (count > 1) {
      setTimer('images', function () { showSlide(state.imageIndex + 1); }, (cfg.display.rotateSeconds || 12) * 1000);
    } else {
      clearTimer('images');
    }
  }

  /* ------------------------------------------------------ kotak 5: video */

  function renderEmbedInStage(stage, embed, captionEl) {
    var previous = stage.querySelectorAll('.video-frame, video');
    for (var i = 0; i < previous.length; i += 1) previous[i].parentNode.removeChild(previous[i]);

    var node;
    if (embed.type === 'video') {
      node = document.createElement('video');
      node.src = embed.url;
      node.muted = true;
      node.autoplay = true;
      node.loop = true;
      node.playsInline = true;
      node.setAttribute('muted', '');
      node.setAttribute('playsinline', '');
    } else {
      node = document.createElement('iframe');
      node.src = embed.url;
      node.loading = 'lazy';
      node.allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen';
      node.setAttribute('scrolling', 'no');
    }
    node.className = 'video-frame';
    stage.insertBefore(node, captionEl);
  }

  function showVideo(index) {
    var cfg = state.cfg;
    var items = cfg.gallery.videos || [];
    var stage = $('videoStage');
    var empty = $('videoEmpty');
    var caption = $('videoCaption');

    if (!items.length) {
      var old = stage.querySelectorAll('.video-frame, video');
      for (var i = 0; i < old.length; i += 1) old[i].parentNode.removeChild(old[i]);
      empty.hidden = false;
      caption.textContent = '';
      buildDots($('videoDots'), 0, 0);
      clearTimer('videos');
      return;
    }

    empty.hidden = true;
    state.videoIndex = ((index % items.length) + items.length) % items.length;
    var item = items[state.videoIndex];
    caption.textContent = item.caption || '';
    buildDots($('videoDots'), items.length, state.videoIndex);

    var embed = embedFor(item.url);
    if (!embed) {
      var nodes = stage.querySelectorAll('.video-frame, video');
      for (var j = 0; j < nodes.length; j += 1) nodes[j].parentNode.removeChild(nodes[j]);
      empty.hidden = false;
      empty.innerHTML = 'Link video tidak dikenali.<br><small>' + escapeHtml(item.url) + '</small>';
      return;
    }
    if (embed.type === 'image') {
      var stale = stage.querySelectorAll('.video-frame, video');
      for (var k = 0; k < stale.length; k += 1) stale[k].parentNode.removeChild(stale[k]);
      var img = document.createElement('img');
      img.className = 'video-frame slide is-active';
      img.src = embed.url;
      img.alt = '';
      stage.insertBefore(img, caption);
      return;
    }
    renderEmbedInStage(stage, embed, caption);
  }

  function startVideoRotation() {
    var cfg = state.cfg;
    var count = (cfg.gallery.videos || []).length;
    showVideo(0);
    if (count > 1) {
      setTimer('videos', function () { showVideo(state.videoIndex + 1); }, (cfg.display.videoSeconds || 30) * 1000);
    } else {
      clearTimer('videos');
    }
  }

  /* ------------------------------------------------------------- DDMS */

  function loadFrame(force) {
    var cfg = state.cfg;
    var frame = $('ddmsFrame');
    var overlay = $('stageOverlay');
    if (!cfg.ddms.enabled) {
      overlay.hidden = false;
      frame.src = 'about:blank';
      setStatus('warn', 'DDMS nonaktif');
      return;
    }
    overlay.hidden = true;
    var target = cfg.ddms.path || '/ddms';
    if (force || frame.getAttribute('src') !== target) {
      frame.src = target;
      state.frameLoadedAt = Date.now();
      setStatus('warn', 'Menghubungkan…');
    }
    if (cfg.ddms.reloadMinutes > 0) {
      setTimer('frameReload', function () {
        if (isInstanceHidden()) return;
        frame.src = 'about:blank';
        setTimeout(function () { frame.src = target; }, 800);
      }, cfg.ddms.reloadMinutes * 60 * 1000);
    } else {
      clearTimer('frameReload');
    }
  }

  function setupFrameEvents() {
    var frame = $('ddmsFrame');
    frame.addEventListener('load', function () {
      if (!state.cfg || !state.cfg.ddms.enabled) return;
      if (!/^about:/.test(frame.getAttribute('src') || '')) {
        setStatus('ok', 'DDMS terhubung');
        state.frameLoadedAt = Date.now();
      }
    });
    window.addEventListener('message', function (event) {
      var data = event.data;
      if (!data || data.type !== 'ahass-ddms-status') return;
      if (data.ok) setStatus('ok', 'DDMS terhubung');
      else setStatus('err', 'DDMS terputus');
    });
  }

  /* --------------------------------------------------------------- config */

  function applyConfig(cfg) {
    state.cfg = cfg;

    document.documentElement.style.setProperty('--left', (cfg.display.leftPercent || 30) + '%');
    document.documentElement.setAttribute('data-theme', cfg.display.theme === 'light' ? 'light' : 'dark');
    document.body.classList.toggle('kiosk', cfg.display.cursorHidden !== false);

    // logo
    if (cfg.logo) {
      var logo = $('logoImg');
      if (logo.getAttribute('src') !== cfg.logo.url) logo.src = cfg.logo.url;
      $('logoTItle').textContent = cfg.logo.title || 'AHASS';
      $('logoSub').textContent = cfg.logo.subtitle || '';
      $('brandMini').textContent = (cfg.logo.title || 'AHASS').split(' ')[0];
    }

    tickClock();
    startImageRotation();
    startVideoRotation();
    loadReviews(false);
    loadFrame(false);
  }

  function loadConfig() {
    return fetch('/__ahass/api/config', { cache: 'no-store' })
      .then(function (r) { return r.json(); })
      .then(function (cfg) {
        var signature = JSON.stringify(cfg);
        var first = !state.signature;
        if (!first && signature === state.signature) return;
        state.signature = signature;
        applyConfig(cfg);
        if (!first) setStatus('warn', 'Pengaturan diperbarui');
      })
      .catch(function (err) {
        setStatus('err', 'Gagal memuat pengaturan');
        console.error('[ahass]', err);
      });
  }

  function connectEvents() {
    if (!window.EventSource) return;
    var source = new EventSource('/__ahass/api/events');
    source.onmessage = function (event) {
      var data;
      try { data = JSON.parse(event.data); } catch (_e) { return; }
      if (data.type === 'config') loadConfig();
    };
    source.onerror = function () {
      source.close();
      setTimeout(connectEvents, 10000);
    };
  }

  /* ---------------------------------------------------------------- init */

  function init() {
    tickClock();
    setInterval(tickClock, 1000);
    setupFrameEvents();
    loadConfig().then(function () {
      if (!state.cfg) return;
      checkHealth();
    });
    setInterval(checkHealth, 120000);
    connectEvents();

    document.addEventListener('contextmenu', function (e) { e.preventDefault(); });
    document.addEventListener('dragstart', function (e) { e.preventDefault(); });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
}());
