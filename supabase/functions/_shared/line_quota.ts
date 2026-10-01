/**
 * LINE Messaging API free-plan monthly quota guard + daily send budget.
 * When LINE returns 429 "monthly limit", pause digests until next Bangkok month.
 * Daily digests share a budget: normal sends stop at 5/day, urgent sends may continue up to 10/day.
 */
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

const QUOTA_KEY = "lineMessagingQuotaBlockUntil";
const BUDGET_KEY = "lineDailySendBudget";

/** Normal cap for automatic digest pushes per Bangkok calendar day */
export const LINE_DAILY_SEND_LIMIT = 5;
/** Hard ceiling on days with urgent updates (first daily report, fuel delivery, explicit urgent) */
export const LINE_DAILY_URGENT_SEND_LIMIT = 10;

export function dailySendLimitFor(urgent: boolean): number {
  return urgent ? LINE_DAILY_URGENT_SEND_LIMIT : LINE_DAILY_SEND_LIMIT;
}

/**
 * Urgent = may use the 6th–10th slot of the day.
 * - send_first: the main daily report of a digest must not be starved by routine updates
 * - explicit: caller passed `{ "urgent": true }`
 * - extra: digest-specific signal (e.g. fuel delivery into the main tank)
 */
export function isUrgentDigestSend(opts: {
  decision: string;
  explicit?: boolean;
  extra?: boolean;
}): boolean {
  return opts.explicit === true || opts.extra === true || opts.decision === "send_first";
}

export function dailyBudgetExhaustedHintTh(urgent: boolean): string {
  return urgent
    ? `ครบเพดานส่ง LINE วันละ ${LINE_DAILY_URGENT_SEND_LIMIT} ข้อความ (รวมอัปเดตด่วน) แล้ว — รอวันถัดไป (หรือส่งด้วย force)`
    : `ครบงบส่ง LINE ปกติวันละ ${LINE_DAILY_SEND_LIMIT} ข้อความแล้ว — อัปเดตทั่วไปรอวันถัดไป (อัปเดตด่วนส่งได้ถึง ${LINE_DAILY_URGENT_SEND_LIMIT})`;
}

function bangkokYmdParts(d = new Date()): { y: number; m: number; day: number } {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Bangkok",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(d);
  const y = Number(parts.find((p) => p.type === "year")?.value ?? "0");
  const m = Number(parts.find((p) => p.type === "month")?.value ?? "0");
  const day = Number(parts.find((p) => p.type === "day")?.value ?? "0");
  return { y, m, day };
}

export function bangkokYmd(d = new Date()): string {
  const { y, m, day } = bangkokYmdParts(d);
  return `${y}-${String(m).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

/** ISO timestamp for 00:00 Asia/Bangkok on the 1st of next month */
export function nextBangkokMonthStartIso(from = new Date()): string {
  const { y, m } = bangkokYmdParts(from);
  const nextY = m === 12 ? y + 1 : y;
  const nextM = m === 12 ? 1 : m + 1;
  // Asia/Bangkok is UTC+7 → 00:00 BKK = previous day 17:00 UTC
  return new Date(Date.UTC(nextY, nextM - 1, 1, -7, 0, 0)).toISOString();
}

export function isLineQuotaBlockedFromDefaults(
  defaults: Record<string, unknown> | null | undefined,
  now = new Date(),
): boolean {
  if (!defaults) return false;
  const raw = defaults[QUOTA_KEY];
  if (typeof raw !== "string" || !raw.trim()) return false;
  const until = Date.parse(raw);
  if (!Number.isFinite(until)) return false;
  return now.getTime() < until;
}

export type LineDailySendBudget = {
  ymd: string;
  count: number;
  limit: number;
  urgentLimit: number;
};

export function readDailySendBudget(
  defaults: Record<string, unknown> | null | undefined,
  ymd: string,
): LineDailySendBudget {
  const base = {
    ymd,
    count: 0,
    limit: LINE_DAILY_SEND_LIMIT,
    urgentLimit: LINE_DAILY_URGENT_SEND_LIMIT,
  };
  const raw = defaults?.[BUDGET_KEY];
  if (raw && typeof raw === "object") {
    const o = raw as Record<string, unknown>;
    const storedYmd = String(o.ymd ?? "").trim();
    const count = Number(o.count);
    if (storedYmd === ymd && Number.isFinite(count) && count >= 0) {
      return { ...base, count: Math.floor(count) };
    }
  }
  return base;
}

/** urgent=false → stop at 5; urgent=true → stop at 10 */
export function isDailySendBudgetExhausted(
  defaults: Record<string, unknown> | null | undefined,
  ymd: string,
  urgent = false,
): boolean {
  return readDailySendBudget(defaults, ymd).count >= dailySendLimitFor(urgent);
}

async function writeAppDefaultsKey(
  admin: SupabaseClient,
  key: string,
  value: unknown,
): Promise<void> {
  const { error: rpcErr } = await admin.rpc("set_app_defaults_key", {
    p_key: key,
    p_value: value,
  });
  if (!rpcErr) return;

  console.warn(`set_app_defaults_key(${key}) failed, fallback upsert`, rpcErr.message);
  const { data, error } = await admin
    .from("app_settings")
    .select("app_defaults")
    .eq("id", "default")
    .maybeSingle();
  if (error) throw error;
  const defaults = {
    ...((data?.app_defaults as Record<string, unknown> | null) ?? {}),
    [key]: value,
  };
  const { error: upErr } = await admin
    .from("app_settings")
    .upsert({ id: "default", app_defaults: defaults }, { onConflict: "id" });
  if (upErr) throw upErr;
}

/** +1 after a successful LINE digest push (shared across vehicle / fuel / attendance). */
export async function incrementDailySendBudget(
  admin: SupabaseClient,
  ymd: string,
): Promise<LineDailySendBudget> {
  const { data, error } = await admin
    .from("app_settings")
    .select("app_defaults")
    .eq("id", "default")
    .maybeSingle();
  if (error) throw error;
  const defaults = (data?.app_defaults ?? {}) as Record<string, unknown>;
  const prev = readDailySendBudget(defaults, ymd);
  const next: LineDailySendBudget = { ...prev, count: prev.count + 1 };
  await writeAppDefaultsKey(admin, BUDGET_KEY, next);
  return next;
}

export async function markLineQuotaBlocked(
  admin: SupabaseClient,
  untilIso = nextBangkokMonthStartIso(),
): Promise<string> {
  await writeAppDefaultsKey(admin, QUOTA_KEY, untilIso);
  return untilIso;
}

export function notifyLooksLikeMonthlyQuota(notifyJson: unknown): boolean {
  if (!notifyJson || typeof notifyJson !== "object") return false;
  const o = notifyJson as Record<string, unknown>;
  const status = Number(o.lineStatus ?? 0);
  const msg = String(o.lineMessage ?? o.message ?? "").toLowerCase();
  const detail =
    o.detail && typeof o.detail === "object"
      ? String((o.detail as Record<string, unknown>).message ?? "").toLowerCase()
      : "";
  return (
    status === 429 ||
    msg.includes("monthly limit") ||
    detail.includes("monthly limit")
  );
}
