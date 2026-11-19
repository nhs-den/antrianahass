#!/usr/bin/env node
'use strict';

/**
 * Reset password admin panel.
 *
 *   sudo -u ahass AHASS_DATA_DIR=/var/lib/antrianahass node scripts/reset-password.js
 *   sudo -u ahass AHASS_DATA_DIR=/var/lib/antrianahass node scripts/reset-password.js "PasswordBaru123"
 */

const config = require('../lib/config');

const provided = process.argv[2];
const cfg = config.get();
const password = provided || config.generatePassword();

if (password.length < 6) {
  console.error('Password minimal 6 karakter.');
  process.exit(1);
}

config.setAdminPassword(cfg, password);
config.save();

console.log('');
console.log('Password admin panel berhasil direset.');
console.log('  Data dir : ' + config.DATA_DIR);
console.log('  Password : ' + password);
console.log('');
console.log('Restart layanan agar sesi lama berakhir:');
console.log('  sudo systemctl restart ahass-panel');
console.log('');
