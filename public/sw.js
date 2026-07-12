/**
 * Minimal app shell SW. Hashed Vite chunks under /assets/ must NOT be served stale
 * from this cache — after a deploy, old index-*.js would request removed AdminModule-*.js
 * and the app breaks with "Failed to fetch dynamically imported module".
 */
const CACHE_NAME = 'cm-app-shell-v3';

self.addEventListener('message', (event) => {
    if (event.data?.type === 'SKIP_WAITING') {
        self.skipWaiting();
    }
});

self.addEventListener('install', (event) => {
    event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches
            .keys()
            .then((keys) =>
                Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))),
            )
            .then(() => self.clients.claim()),
    );
});

self.addEventListener('fetch', (event) => {
    const req = event.request;
    if (req.method !== 'GET') return;
    const url = new URL(req.url);
    if (url.origin !== self.location.origin) return;

    // Build output: always network (no SW stale body for hashed filenames).
    if (url.pathname.startsWith('/assets/')) {
        event.respondWith(fetch(req));
        return;
    }

    // SPA: always hit network for HTML navigations (avoids stale index referencing old chunks).
    if (req.mode === 'navigate') {
        event.respondWith(fetch(req).catch(() => caches.match('/index.html')));
        return;
    }

    // Manifest / icons: network first, cache fallback for offline install metadata.
    if (url.pathname === '/manifest.webmanifest' || url.pathname.startsWith('/icons/')) {
        event.respondWith(
            fetch(req)
                .then((resp) => {
                    if (resp.ok) {
                        const copy = resp.clone();
                        caches.open(CACHE_NAME).then((cache) => cache.put(req, copy));
                    }
                    return resp;
                })
                .catch(() => caches.match(req)),
        );
    }
});
