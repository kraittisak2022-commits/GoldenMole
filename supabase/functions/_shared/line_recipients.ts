/** Filter LINE recipient IDs from env CSV. */
export function canonicalLineRecipientId(raw: string): string | null {
  const s = raw.trim();
  const m = s.match(/^([UCR])([a-f0-9]{32})$/i);
  if (!m) return null;
  return `${m[1].toUpperCase()}${m[2].toLowerCase()}`;
}

export function parseAllRecipientIds(raw: string): string[] {
  return [
    ...new Set(
      raw
        .split(/[,;\s]+/)
        .map((x) => canonicalLineRecipientId(x))
        .filter((x): x is string => !!x),
    ),
  ];
}

/** รายงานเข้ากลุ่ม/ห้องเท่านั้น (C… / R…) */
export function parseGroupReportRecipientIds(raw: string): string[] {
  return parseAllRecipientIds(raw).filter((id) => !id.startsWith("U"));
}

/** ผู้ใช้ที่ถาม–ตอบในแชทส่วนตัวได้ (U…) */
export function parseQaUserIds(raw: string): string[] {
  return parseAllRecipientIds(raw).filter((id) => id.startsWith("U"));
}
