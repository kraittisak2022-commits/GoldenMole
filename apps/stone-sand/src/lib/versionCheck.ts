type Fetcher = (input: string, init?: RequestInit) => Promise<Pick<Response, 'ok' | 'json'>>;

/** Build id of the deploy that is live right now, or null when it cannot be read. */
export async function fetchLatestBuildId(fetcher: Fetcher = fetch): Promise<string | null> {
  try {
    const res = await fetcher(`/version.json?t=${Date.now()}`, { cache: 'no-store' });
    if (!res.ok) return null;
    const body = (await res.json()) as { buildId?: unknown };
    return typeof body.buildId === 'string' && body.buildId ? body.buildId : null;
  } catch {
    return null;
  }
}

export function isOutdated(current: string, latest: string | null): boolean {
  return current !== 'dev' && !!latest && latest !== current;
}
