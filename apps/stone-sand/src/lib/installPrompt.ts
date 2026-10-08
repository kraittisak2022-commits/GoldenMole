import { useSyncExternalStore } from 'react';

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

let deferred: BeforeInstallPromptEvent | null = null;
const listeners = new Set<() => void>();
const notify = () => listeners.forEach((l) => l());

if (typeof window !== 'undefined') {
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferred = e as BeforeInstallPromptEvent;
    notify();
  });
  window.addEventListener('appinstalled', () => {
    deferred = null;
    notify();
  });
}

const subscribe = (l: () => void) => {
  listeners.add(l);
  return () => listeners.delete(l);
};

export function isStandalone(): boolean {
  return (
    window.matchMedia('(display-mode: standalone)').matches ||
    (navigator as Navigator & { standalone?: boolean }).standalone === true
  );
}

export const isIos = () => /iphone|ipad|ipod/i.test(navigator.userAgent);

/** null when the browser has not offered an install. */
export function useInstallPrompt(): (() => Promise<void>) | null {
  const event = useSyncExternalStore(subscribe, () => deferred, () => null);
  if (!event) return null;
  return async () => {
    await event.prompt();
    await event.userChoice;
    deferred = null;
    notify();
  };
}
