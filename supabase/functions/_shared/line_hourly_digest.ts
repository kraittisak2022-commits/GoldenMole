/**
 * Daily LINE digest helpers:
 * - รายงานหลักวันละครั้ง (เมื่อมีข้อมูลครั้งแรก)
 * - รอบถัดไปส่งเฉพาะรายการใหม่เท่านั้น ไม่ส่งของเก่าซ้ำ
 */

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

export type LineDigestState = {
  ymd: string;
  fingerprint: string;
  /** keys ของรายการที่ส่งไปแล้วในวันนั้น */
  items?: string[];
  sentAt?: string;
};

export function bangkokHour(d = new Date()): number {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Bangkok",
    hour: "2-digit",
    hour12: false,
  }).formatToParts(d);
  return Number(parts.find((p) => p.type === "hour")?.value ?? "0");
}

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

export function digestStatePayload(state: LineDigestState): Record<string, unknown> {
  return {
    ymd: state.ymd,
    fingerprint: state.fingerprint,
    items: state.items ?? [],
    sentAt: state.sentAt ?? new Date().toISOString(),
  };
}

/** เขียนเฉพาะคีย์ digest — กัน race ตอน cron พร้อมกันทับ app_defaults ทั้งก้อน */
export async function persistDigestState(
  admin: SupabaseClient,
  key: string,
  state: LineDigestState,
): Promise<void> {
  const payload = digestStatePayload(state);
  const { error: rpcErr } = await admin.rpc("set_app_defaults_key", {
    p_key: key,
    p_value: payload,
  });
  if (!rpcErr) return;

  // fallback ถ้ายังไม่มี RPC
  console.warn("set_app_defaults_key RPC missing/failed, fallback upsert", rpcErr.message);
  const { data, error } = await admin
    .from("app_settings")
    .select("app_defaults")
    .eq("id", "default")
    .maybeSingle();
  if (error) throw error;
  const defaults = {
    ...((data?.app_defaults as Record<string, unknown> | null) ?? {}),
    [key]: payload,
  };
  const { error: upErr } = await admin
    .from("app_settings")
    .upsert({ id: "default", app_defaults: defaults }, { onConflict: "id" });
  if (upErr) throw upErr;
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

/** รวมคีย์ที่ส่งแล้ว + คีย์ใหม่ที่เพิ่งส่ง */
export function unionSentKeys(
  saved: LineDigestState | null,
  dateYmd: string,
  justSent: string[],
): string[] {
  const prev = saved && saved.ymd === dateYmd ? (saved.items ?? []) : [];
  return [...new Set([...prev, ...justSent])];
}

/**
 * send_first = รายงานหลักครั้งแรกของวัน
 * send_update = มีรายการใหม่เท่านั้น
 * skip_unchanged = ไม่ส่ง (กันแชทรก)
 */
export function digestSendDecision(opts: {
  force: boolean;
  testPersonalOnly: boolean;
  dateYmd: string;
  fingerprint: string;
  saved: LineDigestState | null;
  newItemCount?: number;
}): "send_first" | "send_update" | "skip_unchanged" {
  if (opts.force || opts.testPersonalOnly) {
    return opts.saved?.ymd === opts.dateYmd ? "send_update" : "send_first";
  }

  const alreadyToday = !!(opts.saved && opts.saved.ymd === opts.dateYmd);
  const newCount = opts.newItemCount ?? 0;

  // เคยส่งวันนี้แล้ว → ส่งได้แค่เมื่อมีรายการใหม่
  if (alreadyToday) {
    if (newCount > 0) return "send_update";
    return "skip_unchanged";
  }

  // ยังไม่เคยส่งวันนี้ → รายงานหลัก 1 ครั้ง (ต้องมีข้อมูล)
  if (opts.fingerprint) return "send_first";
  return "skip_unchanged";
}

export function fingerprintParts(parts: Array<string | number>): string {
  return parts.map((p) => String(p)).join("|");
}
