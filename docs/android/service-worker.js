// Service Worker Poof PWA — cache basique pour offline + installable
const CACHE_VERSION = "poof-v1";
const CACHE_ASSETS = [
    "/Home.html",
    "/Home.style.css",
    "/manifest.json",
    "/icons/icon-192.png",
    "/icons/icon-512.png",
    "/icons/apple-touch-icon.png"
];

// Install : pré-cache les assets essentiels
self.addEventListener("install", (event) => {
    event.waitUntil(
        caches.open(CACHE_VERSION).then((cache) => cache.addAll(CACHE_ASSETS))
    );
    self.skipWaiting();
});

// Activate : nettoie les vieux caches
self.addEventListener("activate", (event) => {
    event.waitUntil(
        caches.keys().then((keys) =>
            Promise.all(keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k)))
        )
    );
    self.clients.claim();
});

// Fetch : cache-first (répond depuis le cache si dispo, sinon réseau)
self.addEventListener("fetch", (event) => {
    if (event.request.method !== "GET") return;
    event.respondWith(
        caches.match(event.request).then((cached) => cached || fetch(event.request))
    );
});
