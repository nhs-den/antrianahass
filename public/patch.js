/* Dijalankan di dalam halaman DDMS (lewat proxy) agar semua panggilan ke
   host asli tetap melewati panel kita (cookie & login tetap valid). */
(function () {
  'use strict';
  var info = window.__AHASS_PROXY__;
  if (!info || !info.host) return;
  var upstreamHost = info.host;

  function mapToLocal(url) {
    try {
      var u = new URL(String(url), location.href);
      if (u.host === upstreamHost) return u.pathname + u.search + u.hash;
    } catch (_err) { /* biarkan */ }
    return url;
  }

  function mapWs(url) {
    try {
      var u = new URL(String(url), location.href);
      if (u.host === upstreamHost) {
        var scheme = location.protocol === 'https:' ? 'wss:' : 'ws:';
        return scheme + '//' + location.host + u.pathname + u.search;
      }
    } catch (_err) { /* biarkan */ }
    return url;
  }

  // fetch
  var nativeFetch = window.fetch;
  if (nativeFetch) {
    window.fetch = function (input, init) {
      if (typeof input === 'string') {
        input = mapToLocal(input);
      } else if (window.URL && input instanceof URL) {
        input = mapToLocal(input.href);
      } else if (input && typeof input === 'object' && input.url) {
        var mapped = mapToLocal(input.url);
        if (mapped !== input.url) {
          try { input = new Request(mapped, input); } catch (_e) { /* pakai aslinya */ }
        }
      }
      return nativeFetch.call(this, input, init);
    };
  }

  // XMLHttpRequest
  if (window.XMLHttpRequest) {
    var nativeOpen = window.XMLHttpRequest.prototype.open;
    window.XMLHttpRequest.prototype.open = function (method, url) {
      var args = Array.prototype.slice.call(arguments);
      args[1] = mapToLocal(url);
      return nativeOpen.apply(this, args);
    };
  }

  // WebSocket
  if (window.WebSocket) {
    var NativeWS = window.WebSocket;
    var PatchedWS = function (url, protocols) {
      return protocols === undefined ? new NativeWS(mapWs(url)) : new NativeWS(mapWs(url), protocols);
    };
    PatchedWS.prototype = NativeWS.prototype;
    ['CONNECTING', 'OPEN', 'CLOSING', 'CLOSED'].forEach(function (key) {
      PatchedWS[key] = NativeWS[key];
    });
    window.WebSocket = PatchedWS;
  }

  // EventSource
  if (window.EventSource) {
    var NativeES = window.EventSource;
    var PatchedES = function (url, config) {
      return new NativeES(mapToLocal(url), config);
    };
    PatchedES.prototype = NativeES.prototype;
    ['CONNECTING', 'OPEN', 'CLOSED'].forEach(function (key) {
      PatchedES[key] = NativeES[key];
    });
    window.EventSource = PatchedES;
  }

  // tautan absolut ke host upstream -> tetap di dalam proxy
  document.addEventListener('click', function (event) {
    var anchor = event.target && event.target.closest ? event.target.closest('a[href]') : null;
    if (!anchor) return;
    var href = anchor.getAttribute('href') || '';
    if (href.indexOf('//' + upstreamHost) === 0 || href.indexOf(info.origin) === 0) {
      var mapped = mapToLocal(href);
      anchor.setAttribute('href', mapped);
    }
  }, true);
}());
