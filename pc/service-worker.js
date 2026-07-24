// Poof — self-destructing service worker.
// The previous SW cached the app shell aggressively, which shipped stale HTML/JS
// to Tauri and blocked the switch to the local signaling server. This version
// wipes every cache and unregisters itself the moment it activates.
self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map((k) => caches.delete(k)));
    const regs = await self.registration.unregister();
    const clients = await self.clients.matchAll({ type: 'window' });
    clients.forEach((c) => c.navigate(c.url));
  })());
});

// Never intercept anything — pass all fetches straight to the network.
self.addEventListener('fetch', () => {});
