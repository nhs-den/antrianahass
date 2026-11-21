'use strict';

/**
 * Setelan layar perangkat (khusus Raspberry Pi) untuk halaman admin.
 *
 * Yang ditangani:
 *   - membaca resolusi aktif (/sys/class/graphics/fb0/virtual_size)
 *   - membaca & menulis mode HDMI di /boot/firmware/config.txt
 *   - mematikan overscan TV (disable_overscan=1)
 *
 * Aman di mesin non-Pi: semua fungsi melaporkan `supported: false` dan
 * pemanggil tidak melakukan perubahan apa pun.
 *
 * PENTING: menulis config.txt tidak langsung berlaku; butuh reboot. Karena itu
 * endpoint pemanggil melakukan reboot sendiri setelah memberi jawaban HTTP.
 */

const fs = require('fs');
const path = require('path');

/* Mode CEA (hdmi_group=1) → ukuran. Diambil dari tabel Raspberry Pi resmi,
 * hanya yang masuk akal untuk panel kiosk. */
const MODES = [
  { mode: 16, size: '1920x1080', label: '1080p60' },
  { mode: 4, size: '1280x720', label: '720p60' },
  { mode: 5, size: '1920x1080', label: '1080i60' },
  { mode: 19, size: '1280x720', label: '720p50' },
  { mode: 31, size: '1920x1080', label: '1080p50' },
  { mode: 9, size: '1360x768', label: '1360x768' },
  { mode: 32, size: '1600x900', label: '1600x900' },
  { mode: 35, size: '1024x768', label: '1024x768' },
  { mode: 29, size: '1440x900', label: '1440x900 (DMT)' }
];

function configTxtPath() {
  const candidates = ['/boot/firmware/config.txt', '/boot/config.txt'];
  for (const file of candidates) {
    try {
      if (fs.existsSync(file)) return file;
    } catch (_err) { /* lanjut */ }
  }
  return null;
}

function isRaspberryPi() {
  try {
    const model = fs.readFileSync('/proc/device-tree/model', 'utf8').replace(/\0/g, '');
    return /raspberry pi/i.test(model);
  } catch (_err) {
    return false;
  }
}

/** Resolusi yang sedang aktif menurut framebuffer. */
function currentResolution() {
  try {
    const raw = fs.readFileSync('/sys/class/graphics/fb0/virtual_size', 'utf8').trim();
    return raw.replace(',', 'x');
  } catch (_err) {
    return '';
  }
}

/** Baca hdmi_group/hdmi_mode/disable_overscan dari config.txt. */
function readConfigTxt() {
  const file = configTxtPath();
  if (!file) return { file: null, hdmiGroup: null, hdmiMode: null, overscanDisabled: false };
  let text = '';
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch (_err) {
    return { file, hdmiGroup: null, hdmiMode: null, overscanDisabled: false };
  }

  const readInt = (key) => {
    const re = new RegExp('^\\s*' + key + '\\s*=\\s*(\\d+)', 'm');
    const m = text.match(re);
    return m ? Number(m[1]) : null;
  };

  // disable_overscan=1 atau baris "disable_overscan" tanpa nilai.
  const overscanOff = /^\s*disable_overscan\s*=\s*1\s*$/m.test(text) ||
    /^\s*disable_overscan\s*$/m.test(text);

  return {
    file,
    hdmiGroup: readInt('hdmi_group'),
    hdmiMode: readInt('hdmi_mode'),
    overscanDisabled: overscanOff
  };
}

/** Ringkasan untuk admin. */
function info() {
  const supported = isRaspberryPi() && !!configTxtPath();
  const cfg = readConfigTxt();
  const current = currentResolution();

  let source = '';
  if (cfg.file) {
    const idx = cfg.file.indexOf('/boot/firmware');
    source = idx === 0 ? '/boot/firmware/config.txt' : cfg.file;
  }

  return {
    supported,
    current,
    source,
    hdmiGroup: cfg.hdmiGroup,
    hdmiMode: cfg.hdmiMode,
    overscanDisabled: cfg.overscanDisabled,
    modes: MODES,
    // Mode yang cocok dengan layar sekarang (kalau ada), untuk preselect.
    match: (MODES.find((m) => m.size === current) || {}).size || ''
  };
}

/** Cari baris mode yang ukurannya paling dekat dengan target. */
function pickMode(width, height) {
  const want = width + 'x' + height;
  const exact = MODES.find((m) => m.size === want);
  if (exact) return exact;
  // Tidak ada yang persis: pilih rasio 16:9 terdekat agar tidak gepeng.
  const wantPixels = width * height;
  const ratio = width / height;
  const candidates = MODES.filter((m) => {
    const [w, h] = m.size.split('x').map(Number);
    return Math.abs(w / h - ratio) < 0.02;
  });
  if (!candidates.length) return null;
  let best = null;
  let bestDiff = Infinity;
  for (const m of candidates) {
    const [w, h] = m.size.split('x').map(Number);
    const diff = Math.abs(w * h - wantPixels);
    if (diff < bestDiff) { best = m; bestDiff = diff; }
  }
  return best;
}

/**
 * Tulis setelan ke config.txt. Mengembalikan ringkasan perubahan.
 * Melempar error bila perangkat tidak didukung.
 */
function apply(options) {
  const opts = options || {};
  if (!isRaspberryPi()) {
    const err = new Error('Setelan resolusi hanya tersedia di Raspberry Pi.');
    err.code = 'UNSUPPORTED';
    throw err;
  }
  const file = configTxtPath();
  if (!file) {
    const err = new Error('config.txt tidak ditemukan.');
    err.code = 'UNSUPPORTED';
    throw err;
  }

  let text = fs.readFileSync(file, 'utf8');
  const changes = [];

  if (opts.width && opts.height) {
    const mode = pickMode(Number(opts.width), Number(opts.height));
    if (!mode) {
      const err = new Error('Resolusi ' + opts.width + 'x' + opts.height + ' tidak didukung HDMI Pi.');
      err.code = 'INVALID';
      throw err;
    }
    // Buang baris hdmi_group/hdmi_mode lama (termasuk yang dikomentari) agar
    // tidak ada duplikat yang membingungkan.
    //
    // framebuffer_width/height HARUS ikut dibuang: baris itu mengunci ukuran
    // framebuffer lebih kuat daripada hdmi_mode, sehingga perubahan mode tidak
    // akan terlihat di layar selama baris tersebut ada.
    const removedFb = /^\s*framebuffer_(width|height)\s*=/m.test(text);
    text = text.split('\n').filter((line) =>
      !/^\s*#?\s*hdmi_(group|mode)\s*=/.test(line) &&
      !/^\s*#?\s*framebuffer_(width|height)\s*=/.test(line)
    ).join('\n');
    text = text.replace(/\n{3,}/g, '\n\n');

    // Sisipkan setelah baris max_framebuffer atau di akhir.
    const block = '[all]\nhdmi_group=1\nhdmi_mode=' + mode.mode + '\n';
    if (/^\s*\[all\]\s*$/m.test(text)) {
      text = text.replace(/^(\s*\[all\]\s*)$/m, '$1\nhdmi_group=1\nhdmi_mode=' + mode.mode);
    } else {
      text = text.replace(/\s*$/, '\n\n') + block;
    }
    changes.push('mode ' + mode.size + ' (' + mode.label + ')');
    if (removedFb) changes.push('framebuffer_width/height dihapus');
  }

  if (opts.overscan === true) {
    if (/^\s*disable_overscan\s*=\s*1\s*$/m.test(text)) {
      // sudah aktif
    } else if (/^\s*disable_overscan\s*=\s*0\s*$/m.test(text)) {
      text = text.replace(/^\s*disable_overscan\s*=\s*0\s*$/m, 'disable_overscan=1');
      changes.push('overscan dimatikan');
    } else {
      text = text.replace(/\s*$/, '\n') + 'disable_overscan=1\n';
      changes.push('overscan dimatikan');
    }
  }

  const backup = file + '.bak-ahass';
  try {
    fs.copyFileSync(file, backup);
  } catch (_err) { /* backup opsional */ }

  fs.writeFileSync(file, text, 'utf8');
  return { file, changes, backup };
}

module.exports = { info, apply, pickMode, MODES, currentResolution, readConfigTxt };
