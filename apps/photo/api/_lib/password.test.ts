// @vitest-environment node
import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { verifyStoredPassword } from './password';

const hex = (s: string) => createHash('sha256').update(s, 'utf8').digest('hex');

describe('verifyStoredPassword', () => {
  it('checks sha256$<hex> hashes', () => {
    const stored = `sha256$${hex('s3cret')}`;
    expect(verifyStoredPassword(stored, 's3cret')).toBe(true);
    expect(verifyStoredPassword(stored, 'wrong')).toBe(false);
  });

  it('accepts older bare-hex and plain-text rows', () => {
    expect(verifyStoredPassword(hex('s3cret').toUpperCase(), 's3cret')).toBe(true);
    expect(verifyStoredPassword('plain', 'plain')).toBe(true);
    expect(verifyStoredPassword('plain', 'Plain')).toBe(false);
  });

  it('tolerates stray spaces around the typed password', () => {
    expect(verifyStoredPassword(`sha256$${hex('s3cret')}`, ' s3cret ')).toBe(true);
  });

  it('never matches an empty stored value', () => {
    expect(verifyStoredPassword(null, '')).toBe(false);
    expect(verifyStoredPassword('', '')).toBe(false);
  });
});
