import type { Customer } from '../types';
import { digitsOnly } from './format';

/** "เสี่ยบาส, บาส\nเฮียบาส" → ['เสี่ยบาส', 'บาส', 'เฮียบาส'] (trimmed, no blanks or repeats). */
export function parseAliases(text: string): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of text.split(/[,\n،;]+/)) {
    const name = raw.trim().replace(/\s+/g, ' ');
    const key = name.toLowerCase();
    if (!name || seen.has(key)) continue;
    seen.add(key);
    out.push(name);
  }
  return out;
}

export const formatAliases = (aliases: string[]) => aliases.join(', ');

/** Alias that matched the query, so the result can show why it came up. */
export function matchedAlias(c: Pick<Customer, 'name' | 'aliases'>, query: string): string | null {
  const q = query.trim().toLowerCase();
  if (!q || c.name.toLowerCase().includes(q)) return null;
  return c.aliases.find((a) => a.toLowerCase().includes(q)) ?? null;
}

export function matchesCustomer(c: Pick<Customer, 'name' | 'aliases' | 'phone'>, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  const digits = digitsOnly(q);
  return (
    c.name.toLowerCase().includes(q) ||
    c.aliases.some((a) => a.toLowerCase().includes(q)) ||
    (digits.length >= 3 && c.phone.includes(digits))
  );
}
