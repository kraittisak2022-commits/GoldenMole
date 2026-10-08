import { fetchLatestBuildId, isOutdated } from './versionCheck';

const respond = (ok: boolean, body: unknown) => async () => ({ ok, json: async () => body });

describe('fetchLatestBuildId', () => {
  it('reads the build id of the live deploy', async () => {
    expect(await fetchLatestBuildId(respond(true, { buildId: 'abc123' }))).toBe('abc123');
  });

  it('returns null when version.json is missing, malformed or offline', async () => {
    expect(await fetchLatestBuildId(respond(false, {}))).toBeNull();
    expect(await fetchLatestBuildId(respond(true, { nope: 1 }))).toBeNull();
    expect(
      await fetchLatestBuildId(async () => {
        throw new TypeError('Failed to fetch');
      }),
    ).toBeNull();
  });
});

describe('isOutdated', () => {
  it('is outdated only when a different build is live', () => {
    expect(isOutdated('abc', 'def')).toBe(true);
    expect(isOutdated('abc', 'abc')).toBe(false);
    expect(isOutdated('abc', null)).toBe(false);
    expect(isOutdated('dev', 'def')).toBe(false);
  });
});
