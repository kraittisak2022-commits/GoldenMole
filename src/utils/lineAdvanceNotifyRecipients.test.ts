import { describe, expect, it } from 'vitest';
import type { AppSettings } from '../types';
import {
  lineIdKindLabel,
  normalizeLineIdList,
  resolveLineAdvanceNotifyRecipientIds,
} from './lineAdvanceNotifyRecipients';

const group = 'C' + 'a'.repeat(32);
const user = 'U' + 'b'.repeat(32);

describe('normalizeLineIdList', () => {
  it('canonicalizes and dedupes', () => {
    expect(normalizeLineIdList([`${group.toUpperCase()}`, group, 'bad'])).toEqual([group]);
  });
});

describe('lineIdKindLabel', () => {
  it('labels by prefix', () => {
    expect(lineIdKindLabel(group)).toBe('กลุ่ม');
    expect(lineIdKindLabel(user)).toBe('ผู้ใช้ (QA)');
  });
});

describe('resolveLineAdvanceNotifyRecipientIds', () => {
  it('prefers appDefaults over empty', () => {
    const settings = {
      appDefaults: { lineAdvanceNotifyUserIds: [group, user] },
    } as AppSettings;
    expect(resolveLineAdvanceNotifyRecipientIds(settings)).toEqual(
      expect.arrayContaining([group, user]),
    );
    expect(resolveLineAdvanceNotifyRecipientIds(settings, { groupsOnly: true })).toEqual([group]);
  });
});
