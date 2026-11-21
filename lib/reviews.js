'use strict';

/**
 * Widget ulasan Google.
 *
 * Mendukung 3 mode (dipilih dari halaman admin):
 *  1. "places"  -> langsung ke Google Places API (butuh API key + Place ID)
 *  2. "ulasan"  -> mengambil JSON dari service ulasan-google
 *                  (https://github.com/nhs-den/ulasan-google) atau endpoint JSON apa pun
 *  3. "embed"   -> menampilkan halaman ulasan-google apa adanya lewat <iframe>
 *
 * Hasil mode 1 & 2 di-cache di memori supaya hemat CPU/kuota.
 */

const util = require('./util');

const cache = new Map(); // key -> { at, data }

function pick(obj, paths) {
  for (let i = 0; i < paths.length; i += 1) {
    const pathParts = paths[i].split('.');
    let cur = obj;
    let ok = true;
    for (let j = 0; j < pathParts.length; j += 1) {
      if (cur == null || typeof cur !== 'object') { ok = false; break; }
      cur = cur[pathParts[j]];
    }
    if (ok && cur !== undefined && cur !== null && cur !== '') return cur;
  }
  return undefined;
}

function num(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function clampRating(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.min(5, Math.round(n * 10) / 10));
}

/** Ambil array ulasan dari berbagai bentuk JSON. */
function extractArray(json) {
  if (Array.isArray(json)) return json;
  if (!json || typeof json !== 'object') return [];
  const candidates = [
    json.reviews,
    json.data,
    json.items,
    json.results,
    json.list,
    json.result && json.result.reviews,
    json.data && json.data.reviews,
    json.places && json.places[0] && json.places[0].reviews,
    json.result && json.result.data && json.result.data.reviews
  ];
  for (const c of candidates) {
    if (Array.isArray(c)) return c;
    if (c && typeof c === 'object' && Array.isArray(c.reviews)) return c.reviews;
  }
  // fallback: cari array pertama yang isinya objek dengan teks ulasan
  const stack = [json];
  let guard = 0;
  while (stack.length && guard < 50) {
    guard += 1;
    const node = stack.shift();
    if (Array.isArray(node) && node.length && typeof node[0] === 'object') {
      const keys = Object.keys(node[0] || {});
      if (keys.some((k) => /text|review|comment|ulasan/i.test(k))) return node;
    }
    if (node && typeof node === 'object') {
      Object.keys(node).forEach((k) => {
        if (node[k] && typeof node[k] === 'object') stack.push(node[k]);
      });
    }
  }
  return [];
}

function normalizeItems(items, limit) {
  const out = [];
  for (let i = 0; i < items.length && out.length < limit; i += 1) {
    const r = items[i] || {};
    const text = pick(r, [
      'text.text', 'originalText.text', 'text', 'review_text', 'reviewText',
      'comment', 'ulasan', 'content', 'snippet', 'body', 'description'
    ]);
    if (!text) continue;
    const author = pick(r, [
      'authorAttribution.displayName', 'author_name', 'authorName', 'author',
      'user.name', 'userName', 'name', 'reviewer', 'profile_name'
    ]) || 'Pelanggan';
    out.push({
      author: String(author).slice(0, 80),
      avatar: String(pick(r, [
        'authorAttribution.photoUri', 'profile_photo_url', 'profilePhotoUrl',
        'avatar', 'user.image', 'photo', 'authorPhoto'
      ]) || ''),
      url: String(pick(r, [
        'authorAttribution.uri', 'author_url', 'authorUrl', 'url', 'link'
      ]) || ''),
      rating: clampRating(pick(r, ['rating', 'stars', 'score', 'bintang'])),
      text: String(text).replace(/\s+/g, ' ').trim().slice(0, 600),
      time: String(pick(r, [
        'relativePublishTimeDescription', 'relative_time_description',
        'relativeTime', 'time_description', 'time', 'date', 'created_at', 'publishTime'
      ]) || '').slice(0, 60)
    });
  }
  return out;
}

function cacheKey(cfg) {
  const r = cfg.reviews;
  return [r.mode, r.placeId, r.ulasanUrl, r.language, r.maxReviews].join('|');
}

/* ------------------------------------------------------------------ *
 * Google Places API (New)
 * ------------------------------------------------------------------ */

async function fetchJson(url, options, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs || 12000);
  try {
    const res = await fetch(url, Object.assign({ signal: controller.signal }, options));
    const text = await res.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch (_err) {
      json = null;
    }
    if (!res.ok) {
      const message = (json && (json.error && (json.error.message || json.error)) ) || text.slice(0, 300) || ('HTTP ' + res.status);
      const err = new Error(typeof message === 'string' ? message : JSON.stringify(message));
      err.status = res.status;
      throw err;
    }
    return json;
  } finally {
    clearTimeout(timer);
  }
}

function mapPlacesPayload(payload, limit) {
  const place = payload && payload.place ? payload.place : payload;
  const items = normalizeItems((place && place.reviews) || [], limit);
  return {
    mode: 'places',
    name: (place && place.displayName && (place.displayName.text || place.displayName)) || '',
    rating: clampRating(place && place.rating),
    total: num(place && place.userRatingCount),
    url: (place && place.googleMapsUri) || '',
    items: items,
    fetchedAt: new Date().toISOString()
  };
}

async function fetchFromPlaces(cfg) {
  const r = cfg.reviews;
  const apiKey = r.apiKey;
  if (!apiKey) throw new Error('API key Google belum diisi.');
  const query = String(r.placeId || '').trim();
  if (!query) throw new Error('Place ID / nama tempat Google belum diisi.');
  const languageCode = r.language || 'id';

  const looksLikePlaceId = /^(places\/)?(ChIJ|GhIJ)[\w-]+$/.test(query);
  if (looksLikePlaceId) {
    const id = query.replace(/^places\//, '');
    const fields = 'displayName,rating,userRatingCount,reviews,googleMapsUri';
    const url =
      'https://places.googleapis.com/v1/places/' + encodeURIComponent(id) +
      '?languageCode=' + encodeURIComponent(languageCode) + '&fields=' + encodeURIComponent(fields);
    const json = await fetchJson(url, { headers: { 'X-Goog-Api-Key': apiKey } });
    return mapPlacesPayload(json, r.maxReviews);
  }

  // bukan Place ID -> anggap query nama tempat
  const json = await fetchJson(
    'https://places.googleapis.com/v1/places:searchText',
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': 'places.displayName,places.rating,places.userRatingCount,places.reviews,places.googleMapsUri,places.id'
      },
      body: JSON.stringify({ textQuery: query, languageCode: languageCode, maxResultCount: 1 })
    }
  );
  const place = json && json.places && json.places[0];
  if (!place) throw new Error('Tempat tidak ditemukan untuk pencarian: ' + query);
  return mapPlacesPayload(place, r.maxReviews);
}

/* ------------------------------------------------------------------ *
 * Service ulasan-google (JSON)
 * ------------------------------------------------------------------ */

async function fetchFromUlasan(cfg) {
  const r = cfg.reviews;
  const target = util.sanitizeUrl(r.ulasanUrl);
  if (!target || target.startsWith('/')) {
    throw new Error('URL JSON ulasan-google belum diisi / tidak valid.');
  }
  const json = await fetchJson(target, {
    headers: { accept: 'application/json', 'user-agent': 'ahass-panel/1.0' }
  }, 15000);

  const items = normalizeItems(extractArray(json), r.maxReviews);
  const root = (json && json.data && typeof json.data === 'object' && !Array.isArray(json.data)) ? json.data : json;
  return {
    mode: 'ulasan',
    name: String(pick(root, ['name', 'place_name', 'placeName', 'title', 'displayName.text', 'displayName', 'business']) || ''),
    rating: clampRating(pick(root, ['rating', 'average_rating', 'averageRating', 'avg_rating', 'average', 'result.rating'])),
    total: num(pick(root, ['user_ratings_total', 'userRatingCount', 'total', 'total_reviews', 'totalReviews', 'rating_count', 'reviewCount', 'result.user_ratings_total'])),
    url: String(pick(root, ['url', 'maps_url', 'mapsUrl', 'google_maps_url', 'place_url', 'link', 'result.url']) || ''),
    items: items,
    fetchedAt: new Date().toISOString()
  };
}

/* ------------------------------------------------------------------ *
 * Mode "bawaan" (built-in) - tanpa aplikasi ulasan-google terpisah
 * ------------------------------------------------------------------ */

/**
 * Panel menjalankan sendiri loader.js di port 3000 (lihat lib/ulasan-builtin.js)
 * yang membaca URL JSON ulasan. Uji coba di sini supaya admin bisa langsung
 * melihat hasil dan pesan kesalahannya.
 */
async function fetchBuiltin(cfg) {
  const r = cfg.reviews;
  const port = Number((r.script && r.script.port) || 3000);
  const url = 'http://127.0.0.1:' + port + '/reviews.json';
  let json = null;
  try {
    json = await fetchJson(url, { headers: { accept: 'application/json' } }, 8000);
  } catch (err) {
    const hint = (r.script && r.script.dir)
      ? 'Periksa URL JSON di kolom "URL JSON ulasan" atau hentikan aplikasi lain di port ' + port + '.'
      : 'Isi kolom "URL JSON ulasan" dengan alamat JSON ulasan Google, atau arahkan ke folder aplikasi ulasan-google.';
    const wrapped = new Error('Widget bawaan (port ' + port + ') belum bisa diambil: ' + err.message + '. ' + hint);
    wrapped.code = 'REVIEWS_BUILTIN_FAILED';
    throw wrapped;
  }
  const items = normalizeItems(extractArray(json), r.maxReviews);
  const root = (json && json.data && typeof json.data === 'object' && !Array.isArray(json.data)) ? json.data : json;
  return {
    mode: 'script',
    source: 'bawaan',
    name: String(pick(root, ['name', 'place_name', 'placeName', 'title', 'displayName.text', 'displayName', 'business']) || ''),
    rating: clampRating(pick(root, ['rating', 'average_rating', 'averageRating', 'average', 'result.rating'])),
    total: num(pick(root, ['user_ratings_total', 'userRatingCount', 'total', 'total_reviews', 'rating_count', 'reviewCount'])),
    url: String(pick(root, ['url', 'maps_url', 'mapsUrl', 'place_url', 'link', 'result.url']) || ''),
    items: items,
    fetchedAt: new Date().toISOString()
  };
}

/* ------------------------------------------------------------------ */

async function get(cfg, force) {
  const mode = (cfg.reviews && cfg.reviews.mode) || 'off';
  if (mode === 'off') {
    return { mode: 'off', items: [], rating: 0, total: 0, disabled: true };
  }
  if (mode === 'embed') {
    return { mode: 'embed', embedUrl: cfg.reviews.embedUrl || '', items: [], rating: 0, total: 0 };
  }

  // Mode bawaan: panel sendiri yang menyajikan /loader.js + /reviews.json,
  // jadi tidak wajib memasang aplikasi ulasan-google terpisah.
  const scriptCfg = cfg.reviews.script || {};
  if (mode === 'script' && builtinActive(cfg)) {
    return getCached(cfg, force, () => fetchBuiltin(cfg));
  }


  return getCached(cfg, force, () => (mode === 'places' ? fetchFromPlaces(cfg) : fetchFromUlasan(cfg)));
}

/**
 * Apakah widget "bawaan" dipakai?  Benar bila admin tidak menempel kode embed
 * dan tidak menunjuk host aplikasi ulasan-google lain.
 */
function builtinActive(cfg) {
  const s = (cfg.reviews && cfg.reviews.script) || {};
  if (String(s.code || '').trim()) return false;
  if (String(s.host || '').trim()) return false;
  return true;
}

async function getCached(cfg, force, fetcher) {
  const key = cacheKey(cfg);
  const ttl = Math.max(1, num(cfg.reviews.cacheMinutes) || 60) * 60 * 1000;
  const hit = cache.get(key);
  if (!force && hit && Date.now() - hit.at < ttl) {
    return Object.assign({ cached: true, cacheAgeMs: Date.now() - hit.at }, hit.data);
  }

  let data;
  try {
    data = await fetcher();
  } catch (err) {
    if (hit) {
      // tetap tampilkan data lama saat gagal refresh
      return Object.assign({ cached: true, stale: true, error: err.message }, hit.data);
    }
    const wrapped = new Error(err.message || 'Gagal mengambil ulasan');
    wrapped.code = 'REVIEWS_FAILED';
    throw wrapped;
  }

  cache.set(key, { at: Date.now(), data: data });
  // bersihkan entri lama
  for (const [k, v] of cache) {
    if (Date.now() - v.at > 6 * 60 * 60 * 1000) cache.delete(k);
  }
  return Object.assign({ cached: false, cacheAgeMs: 0 }, data);
}

function clearCache() {
  cache.clear();
}

/**
 * Ubah JSON ulasan bentuk apa pun menjadi bentuk seragam panel:
 * { name, rating, total, url, items[] } — dipakai widget bawaan.
 */
function normalizePayload(json, limit) {
  const items = normalizeItems(extractArray(json), limit || 10);
  const root = (json && json.data && typeof json.data === 'object' && !Array.isArray(json.data)) ? json.data : json;
  return {
    name: String(pick(root, ['name', 'place_name', 'placeName', 'title', 'displayName.text', 'displayName', 'business']) || ''),
    rating: clampRating(pick(root, ['rating', 'average_rating', 'averageRating', 'average', 'result.rating'])),
    total: num(pick(root, ['user_ratings_total', 'userRatingCount', 'total', 'total_reviews', 'rating_count', 'reviewCount', 'result.user_ratings_total'])),
    url: String(pick(root, ['url', 'maps_url', 'mapsUrl', 'place_url', 'link', 'result.url']) || ''),
    items: items,
    fetchedAt: new Date().toISOString()
  };
}

module.exports = { get, clearCache, extractArray, normalizeItems, normalizePayload, builtinActive };
