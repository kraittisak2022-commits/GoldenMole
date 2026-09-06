/**
 * Hourly LINE digest helpers: fingerprint + skip-until-data-changes.
 */

export type LineDigestState = {
  ymd: string;
  fingerprint: string;
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
  return {
    ymd,
    fingerprint,
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
    sentAt: state.sentAt ?? new Date().toISOString(),
  };
}

/** ส่งเมื่อ fingerprint ใหม่ของวันนั้น — ข้ามถ้าเหมือนรอบก่อน */
export function digestSendDecision(opts: {
  force: boolean;
  testPersonalOnly: boolean;
  dateYmd: string;
  fingerprint: string;
  saved: LineDigestState | null;
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

/** simple stable fingerprint */
export function fingerprintParts(parts: Array<string | number>): string {
  return parts.map((p) => String(p)).join("|");
}
