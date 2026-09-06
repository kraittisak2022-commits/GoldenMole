/**
 * Hourly LINE digest helpers: fingerprint + send only new items (no resend clutter).
 */

export type LineDigestState = {
  ymd: string;
  fingerprint: string;
  /** keys ของรายการที่ส่งไปแล้วในวันนั้น */
  items?: string[];
  sentAt?: string;
};

export function readDigestState(
  defaults: Record<string, unknown>,
  key: string,
): LineDigestState | null {
  const raw = defaults[key];
  if (!raw || typeof raw !== "object") return null;
  const o = raw as Record<string, unknown>;
  const ymd = String(o.ymd ?? "").trim();
  const fingerprint = String(o.fingerprint ?? "").trim();
  if (!ymd || !fingerprint) return null;
  const items = Array.isArray(o.items)
    ? o.items.map((x) => String(x)).filter(Boolean)
    : [];
  return {
    ymd,
    fingerprint,
    items,
    sentAt: typeof o.sentAt === "string" ? o.sentAt : undefined,
  };
}

export function writeDigestState(
  defaults: Record<string, unknown>,
  key: string,
  state: LineDigestState,
): void {
  defaults[key] = {
    ymd: state.ymd,
    fingerprint: state.fingerprint,
    items: state.items ?? [],
    sentAt: state.sentAt ?? new Date().toISOString(),
  };
}

/** คีย์ที่ยังไม่เคยส่งในวันนั้น */
export function onlyNewKeys(
  currentKeys: string[],
  saved: LineDigestState | null,
  dateYmd: string,
): string[] {
  if (!saved || saved.ymd !== dateYmd) return [...currentKeys];
  const prev = new Set(saved.items ?? []);
  return currentKeys.filter((k) => !prev.has(k));
}

export function mergeSentKeys(
  saved: LineDigestState | null,
  dateYmd: string,
  newlySent: string[],
  allCurrent: string[],
): string[] {
  const base = saved && saved.ymd === dateYmd ? (saved.items ?? []) : [];
  return [...new Set([...base, ...newlySent, ...allCurrent.filter((k) =>
    newlySent.includes(k) || (saved?.ymd === dateYmd && (saved.items ?? []).includes(k))
  )])];
}

/** รวมคีย์ที่ส่งแล้ว + คีย์ใหม่ที่เพิ่งส่ง */
export function unionSentKeys(
  saved: LineDigestState | null,
  dateYmd: string,
  justSent: string[],
): string[] {
  const prev = saved && saved.ymd === dateYmd ? (saved.items ?? []) : [];
  return [...new Set([...prev, ...justSent])];
}

/** ส่งเมื่อ fingerprint ใหม่ของวันนั้น — ข้ามถ้าเหมือนรอบก่อน */
export function digestSendDecision(opts: {
  force: boolean;
  testPersonalOnly: boolean;
  dateYmd: string;
  fingerprint: string;
  saved: LineDigestState | null;
  /** ถ้ามีและว่างบนวันเดิม = ไม่มีของใหม่ */
  newItemCount?: number;
}): "send_first" | "send_update" | "skip_unchanged" {
  if (opts.force || opts.testPersonalOnly) {
    return opts.saved?.ymd === opts.dateYmd ? "send_update" : "send_first";
  }
  if (
    opts.saved &&
    opts.saved.ymd === opts.dateYmd &&
    opts.saved.fingerprint === opts.fingerprint
  ) {
    return "skip_unchanged";
  }
  if (
    opts.saved &&
    opts.saved.ymd === opts.dateYmd &&
    typeof opts.newItemCount === "number" &&
    opts.newItemCount === 0
  ) {
    // fingerprint เปลี่ยนแต่ไม่มีคีย์ใหม่ (เช่น ลบรายการ) — ไม่ส่งซ้ำของเก่า
    return "skip_unchanged";
  }
  if (opts.saved && opts.saved.ymd === opts.dateYmd) {
    return "send_update";
  }
  return "send_first";
}

export function withUpdatePrefix(text: string, isUpdate: boolean): string {
  if (!isUpdate) return text;
  const t = text.trim();
  if (t.startsWith("อัปเดต")) return t;
  return `อัปเดต\n${t}`;
}

export function fingerprintParts(parts: Array<string | number>): string {
  return parts.map((p) => String(p)).join("|");
}
