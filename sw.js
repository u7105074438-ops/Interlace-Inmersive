/* Service worker de Roquet Redemption (cache-first, tolerante a fallos). */
var CACHE = 'roquet-redemption-v3';
var ASSETS = ['./', './index.html', './manifest.webmanifest'];
self.addEventListener('install', function (e) {
  e.waitUntil(caches.open(CACHE).then(function (c) {
    return Promise.all(ASSETS.map(function (a) { return c.add(a).catch(function () {}); }));
  }).then(function () { return self.skipWaiting(); }));
});
self.addEventListener('activate', function (e) {
  e.waitUntil(caches.keys().then(function (ks) {
    return Promise.all(ks.map(function (k) { if (k !== CACHE) return caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});
self.addEventListener('fetch', function (e) {
  if (e.request.method !== 'GET') return;
  e.respondWith(caches.match(e.request).then(function (r) {
    return r || fetch(e.request).then(function (resp) {
      try { var cp = resp.clone(); caches.open(CACHE).then(function (c) { c.put(e.request, cp); }); } catch (x) {}
      return resp;
    }).catch(function () { return caches.match('./index.html'); });
  }));
});
