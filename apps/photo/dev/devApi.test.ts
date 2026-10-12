// @vitest-environment node
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { resolveApiFile } from './devApi';

const apiDir = path.resolve(__dirname, '../api');
const rel = (file: string | null) => file && path.relative(apiDir, file).replace(/\\/g, '/');

describe('resolveApiFile', () => {
  it('maps URLs to api files the way Vercel does', () => {
    expect(rel(resolveApiFile(apiDir, '/api/auth/login'))).toBe('auth/login.ts');
    expect(rel(resolveApiFile(apiDir, '/api/albums'))).toBe('albums/index.ts');
    expect(rel(resolveApiFile(apiDir, '/api/albums/7f1c2b9e-0000-4000-8000-000000000000'))).toBe('albums/[id].ts');
    expect(rel(resolveApiFile(apiDir, '/api/share/abcDEF123_-xyz456789'))).toBe('share/[token].ts');
  });

  it('returns null for unknown paths', () => {
    expect(resolveApiFile(apiDir, '/api/nope/deeper/still')).toBeNull();
    expect(resolveApiFile(apiDir, '/api/')).toBeNull();
  });
});
