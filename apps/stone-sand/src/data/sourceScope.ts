import type { OrderSource } from '../types';

/**
 * The order source the signed-in account is limited to (admin_users.order_source), or null for both.
 * Set by AuthProvider; every order / statement / payout query reads it.
 * UI-level only: the database (RLS allow-all) does not enforce it.
 */
let locked: OrderSource | null = null;

export function setLockedSource(source: OrderSource | null): void {
  locked = source;
}

export function lockedSource(): OrderSource | null {
  return locked;
}

export function canSeeSource(source: OrderSource): boolean {
  return !locked || source === locked;
}

export function parseOrderSource(raw: unknown): OrderSource | null {
  return raw === 'shop' || raw === 'pit' ? raw : null;
}

/** Adds `source = locked` to a PostgREST query when the account is limited. */
export function scoped<Q>(q: Q): Q {
  return locked ? (q as unknown as { eq: (column: string, value: string) => Q }).eq('source', locked) : q;
}
