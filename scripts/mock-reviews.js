#!/usr/bin/env node
'use strict';

/**
 * Endpoint JSON tiruan untuk menguji mode "ulasan" (service ulasan-google).
 *   node scripts/mock-reviews.js          # http://127.0.0.1:9098/reviews
 */

const http = require('http');

const PORT = Number(process.env.MOCK_PORT || 9098);

const payload = {
  place_name: 'AHASS Munjul Motor',
  rating: 4.7,
  user_ratings_total: 213,
  maps_url: 'https://www.google.com/maps/search/?api=1&query=AHASS+Munjul+Motor',
  reviews: [
    {
      author_name: 'Budi Santoso',
      profile_photo_url: '',
      rating: 5,
      relative_time_description: '2 minggu lalu',
      text: 'Servis cepat, mekaniknya ramah dan menjelaskan detail kerusakan. Ruang tunggu nyaman.'
    },
    {
      author_name: 'Siti Aminah',
      profile_photo_url: '',
      rating: 5,
      relative_time_description: 'sebulan lalu',
      text: 'Booking online mudah, motor selesai sesuai estimasi. Harga transparan.'
    },
    {
      author_name: 'Agus Pratama',
      profile_photo_url: '',
      rating: 4,
      relative_time_description: '2 bulan lalu',
      text: 'Antrian agak ramai saat akhir pekan, tapi hasil kerja memuaskan.'
    },
    {
      author_name: 'Dewi Lestari',
      profile_photo_url: '',
      rating: 5,
      relative_time_description: '3 bulan lalu',
      text: 'Pelayanan ramah, ada kopi gratis. Recommended untuk servis Honda.'
    }
  ]
};

http
  .createServer((req, res) => {
    res.writeHead(200, {
      'content-type': 'application/json; charset=utf-8',
      'access-control-allow-origin': '*',
      'cache-control': 'no-store'
    });
    res.end(JSON.stringify(payload));
  })
  .listen(PORT, '0.0.0.0', () => {
    console.log('Mock ulasan berjalan di http://127.0.0.1:' + PORT + '/reviews');
  });
