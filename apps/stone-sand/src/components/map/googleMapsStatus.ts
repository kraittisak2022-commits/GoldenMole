import { useSyncExternalStore } from 'react';

let failed = false;
const listeners = new Set<() => void>();

/** Switches every map to the OpenStreetMap fallback for the rest of the session. */
export function markGoogleMapsFailed(): void {
  if (failed) return;
  failed = true;
  listeners.forEach((l) => l());
}

if (typeof window !== 'undefined') {
  // Google calls this global when the key is invalid, not enabled for Maps JavaScript API, or not allowed for this site.
  (window as unknown as { gm_authFailure?: () => void }).gm_authFailure = markGoogleMapsFailed;
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function useGoogleMapsFailed(): boolean {
  return useSyncExternalStore(subscribe, () => failed);
}
