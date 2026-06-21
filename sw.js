// Service worker minimo: serve solo a rendere l'app installabile come PWA.
// Nessuna cache offline complessa: i dati arrivano sempre da Supabase online,
// quindi non ha senso cacheare le risposte API. Cacheiamo solo lo shell statico.

const CACHE_NAME = "polo-logistico-shell-v1";
const SHELL_FILES = ["./index.html", "./manifest.json"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_FILES))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// Network-first per index.html (così aggiornamenti dell'app si vedono subito),
// fallback alla cache solo se offline.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  event.respondWith(
    fetch(event.request).catch(() => caches.match(event.request))
  );
});
