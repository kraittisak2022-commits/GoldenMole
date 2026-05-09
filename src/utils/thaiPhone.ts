/** Normalize Thai mobile to 10 digits starting with 0 (for SMS APIs). */
export function normalizeThaiPhone(raw: string | undefined | null): string | null {
    const d = String(raw ?? '').replace(/\D/g, '');
    if (!d) return null;
    if (d.length === 10 && d.startsWith('0')) return d;
    if (d.length === 11 && d.startsWith('66')) return `0${d.slice(2)}`;
    if (d.length >= 10) {
        const tail = d.slice(-10);
        return tail.startsWith('0') ? tail : null;
    }
    return null;
}
