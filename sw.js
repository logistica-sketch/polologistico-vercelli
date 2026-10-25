// Service worker: rende l'app installabile come PWA.
// I dati arrivano sempre da Supabase online e le librerie dalle CDN, quindi
// l'app non funziona offline: senza rete le navigazioni ricevono offline.html.
// Cacheiamo solo lo shell statico dello stesso dominio.

const CACHE_NAME = "polo-logistico-shell-v3";
const PAGINA_OFFLINE = "./offline.html";
const SHELL_FILES = [
  "./index.html",
  "./manifest.json",
  "./stile.css",
  PAGINA_OFFLINE,
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/maskable-192.png",
  "./icons/maskable-512.png",
];

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

// Network-first (così gli aggiornamenti dell'app si vedono subito); ogni risposta
// valida aggiorna la copia in cache. Se offline:
//  - navigazione → pagina offline (l'app senza rete non può funzionare);
//  - altri file → copia in cache, altrimenti Response.error().
// Si intercettano solo le richieste dello stesso dominio: Supabase e CDN passano diretti.
self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;
  if (new URL(req.url).origin !== self.location.origin) return;

  event.respondWith(
    fetch(req)
      .then((resp) => {
        if (resp.ok && resp.type === "basic") {
          const copia = resp.clone();
          event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.put(req, copia)));
        }
        return resp;
      })
      .catch(async () => {
        if (req.mode === "navigate") {
          return (await caches.match(PAGINA_OFFLINE)) || Response.error();
        }
        return (await caches.match(req)) || Response.error();
      })
  );
});
