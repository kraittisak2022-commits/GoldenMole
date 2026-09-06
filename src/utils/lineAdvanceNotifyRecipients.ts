import type { AppDefaults, AppSettings } from '../types';
import { normalizeLineRecipientId, normalizeLineUserId, parseLineUserIdsField } from './lineMessaging';

/** รวม ID จากตั้งค่าเว็บ (appDefaults) ก่อน แล้วตามด้วย VITE env */
export function resolveLineAdvanceNotifyRecipientIds(
  settings?: AppSettings | null,
  opts?: { groupsOnly?: boolean },
): string[] {
  const fromSettings = (settings?.appDefaults?.lineAdvanceNotifyUserIds || [])
    .map((raw) => normalizeLineRecipientId(raw) || normalizeLineUserId(raw))
    .filter((x): x is string => !!x);

  const fromEnv = parseLineUserIdsField(
    String(import.meta.env.VITE_LINE_ADVANCE_NOTIFY_USER_IDS || ''),
  );

  const merged = [...new Set(fromSettings.length > 0 ? fromSettings : fromEnv)];
  if (opts?.groupsOnly) {
    return merged.filter((id) => id.startsWith('C') || id.startsWith('R'));
  }
  return merged;
}

export function normalizeLineIdList(rawIds: string[]): string[] {
  return [
    ...new Set(
      rawIds
        .map((raw) => normalizeLineRecipientId(raw) || normalizeLineUserId(raw))
        .filter((x): x is string => !!x),
    ),
  ].sort((a, b) => a.localeCompare(b));
}

export function lineIdKindLabel(id: string): string {
  if (id.startsWith('C')) return 'กลุ่ม';
  if (id.startsWith('R')) return 'ห้อง';
  if (id.startsWith('U')) return 'ผู้ใช้ (QA)';
  return 'อื่น';
}

export type LineSeenChat = NonNullable<
  NonNullable<AppDefaults['lineWebhookSeenChats']>['chats']
>[number];

export function seenChatsFromSettings(settings?: AppSettings | null): LineSeenChat[] {
  const raw = settings?.appDefaults?.lineWebhookSeenChats;
  if (!raw) return [];
  if (Array.isArray(raw)) return raw as LineSeenChat[];
  if (Array.isArray(raw.chats)) return raw.chats;
  return [];
}
