const CACHE_NAME = 'cm-app-shell-v1';
const APP_SHELL = ['/', '/index.html', '/manifest.webmanifest'];

self.addEventListener('install', event => {
    event.waitUntil(
        caches.open(CACHE_NAME).then(cache => cache.addAll(APP_SHELL)).then(() => self.skipWaiting())
    );
});

self.addEventListener('activate', event => {
    event.waitUntil(
        caches.keys().then(keys =>
            Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
        ).then(() => self.clients.claim())
    );
});

self.addEventListener('fetch', event => {
    const req = event.request;
    if (req.method !== 'GET') return;
    const url = new URL(req.url);

    // Navigation requests: network first, fallback to app shell.
    if (req.mode === 'navigate') {
        event.respondWith(
            fetch(req).catch(() => caches.match('/index.html'))
        );
        return;
    }

    // Same-origin static assets: stale-while-revalidate.
    if (url.origin === self.location.origin) {
        event.respondWith(
            caches.match(req).then(cached => {
                const networkFetch = fetch(req).then(resp => {
                    const cloned = resp.clone();
                    caches.open(CACHE_NAME).then(cache => cache.put(req, cloned));
                    return resp;
                }).catch(() => cached);
                return cached || networkFetch;
            })
        );
    }
});
