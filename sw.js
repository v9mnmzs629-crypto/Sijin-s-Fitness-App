// Bump VER on every deploy so phones drop the old cache.
const VER = 'sfa-v2-1';
const CORE = ['./', './index.html', './manifest.json', './icon-192.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VER).then(c => c.addAll(CORE)).catch(() => {}));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (k !== VER) await caches.delete(k);
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.hostname.endsWith('supabase.co')) return;          // never cache your data
  const keep = r => { if (r && (r.ok || r.type === 'opaque')) { const cp = r.clone(); caches.open(VER).then(c => c.put(req, cp)); } return r; };
  if (url.origin === location.origin) {
    // your own files: always try the network first so updates show up, fall back offline
    e.respondWith(fetch(req, { cache: 'no-cache' }).then(keep).catch(() =>
      caches.match(req).then(r => r || caches.match('./index.html'))));
  } else {
    // libraries and fonts: cached after first load, so the app opens offline
    e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(keep)));
  }
});
