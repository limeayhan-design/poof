// Poof service worker — cache app shell + navigation offline fallback.
//
// Bump CACHE_VERSION quand tu modifies mobile.html, manifest ou icônes pour
// forcer les clients installés à recharger le shell (le vieux cache est purgé
// dans `activate`).
const CACHE_VERSION = 'poof-shell-v4';

// App shell = tout ce qu'il faut pour ouvrir mobile.html rapidement.
// Les JS métier (mobile.js + modules ES + vendor) sont cachés aussi pour
// éviter un fetch réseau au boot — mais le signaling / relay HTTPS (fetch
// réseau réel) reste toujours network-first via le passthrough dans fetch().
const SHELL_ASSETS = [
  './mobile.html',
  './manifest.json',
  './mobile.js',
  './src/device-identity.js',
  './src/paired-peer-store.js',
  './vendor/socket.io.min.js',
  './vendor/qrcode.min.js',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/apple-touch-icon.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then((cache) => cache.addAll(SHELL_ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k))
    );
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // Ne jamais intercepter les appels réseau critiques (signaling, relay,
  // API tierces). Cross-origin OU même-origin avec query = passe direct.
  if (url.origin !== self.location.origin) return;
  if (url.pathname.includes('/api/') || url.pathname.includes('/signal')) return;

  // Navigation (l'user tape l'URL / recharge) — network-first pour attraper
  // les updates, fallback cache si offline (offre au moins l'app shell).
  if (req.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        const fresh = await fetch(req);
        const cache = await caches.open(CACHE_VERSION);
        cache.put(req, fresh.clone());
        return fresh;
      } catch {
        const cached = await caches.match('./mobile.html');
        return cached || Response.error();
      }
    })());
    return;
  }

  // Assets statiques (icons, manifest) — cache-first pour vitesse, refresh
  // en arrière-plan si le réseau répond.
  event.respondWith((async () => {
    const cached = await caches.match(req);
    if (cached) {
      fetch(req).then((fresh) => {
        if (fresh && fresh.status === 200) {
          caches.open(CACHE_VERSION).then((c) => c.put(req, fresh));
        }
      }).catch(() => {});
      return cached;
    }
    try {
      const fresh = await fetch(req);
      if (fresh && fresh.status === 200) {
        const cache = await caches.open(CACHE_VERSION);
        cache.put(req, fresh.clone());
      }
      return fresh;
    } catch {
      return Response.error();
    }
  })());
});
