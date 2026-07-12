/** Activate waiting SW and reload when a new deploy is available. */
export function setupServiceWorkerUpdates() {
    if (!('serviceWorker' in navigator)) return;

    navigator.serviceWorker.addEventListener('controllerchange', () => {
        window.location.reload();
    });

    void navigator.serviceWorker.register('/sw.js', { updateViaCache: 'none' }).then((registration) => {
        const activateWaiting = () => {
            if (registration.waiting) {
                registration.waiting.postMessage({ type: 'SKIP_WAITING' });
            }
        };

        if (registration.waiting) {
            activateWaiting();
        }

        registration.addEventListener('updatefound', () => {
            const worker = registration.installing;
            if (!worker) return;
            worker.addEventListener('statechange', () => {
                if (worker.state === 'installed' && navigator.serviceWorker.controller) {
                    activateWaiting();
                }
            });
        });

        // Check for updates when user returns to the tab.
        document.addEventListener('visibilitychange', () => {
            if (document.visibilityState === 'visible') {
                void registration.update();
            }
        });
    });
}
