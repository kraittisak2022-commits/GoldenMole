import { afterEach, describe, expect, it } from 'vitest';
import {
  clearSession,
  readSession,
  saveSession,
  SESSION_TTL_MS,
  type FlowAccountSession,
} from './session';

const sample: FlowAccountSession = {
  id: '1',
  username: 'boss',
  displayName: 'Boss',
  role: 'SuperAdmin',
  loginAt: new Date().toISOString(),
};

describe('session', () => {
  afterEach(() => {
    clearSession();
  });

  it('saves and reads a session', () => {
    saveSession(sample);
    expect(readSession()).toEqual(sample);
  });

  it('clears session on logout', () => {
    saveSession(sample);
    clearSession();
    expect(readSession()).toBeNull();
  });

  it('expires old sessions', () => {
    saveSession({
      ...sample,
      loginAt: new Date(Date.now() - SESSION_TTL_MS - 1000).toISOString(),
    });
    expect(readSession()).toBeNull();
  });
});
