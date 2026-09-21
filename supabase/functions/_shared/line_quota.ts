/**
 * LINE Messaging API free-plan monthly quota guard + daily send budget.
 * When LINE returns 429 "monthly limit", pause digests until next Bangkok month.
 * Daily digests share a soft cap (default 5 messages / day) to save free-plan quota.
 */
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

const QUOTA_KEY = "lineMessagingQuotaBlockUntil";
const BUDGET_KEY = "lineDailySendBudget";

/** Soft cap for automatic digest pushes per Bangkok calendar day */
export const LINE_DAILY_SEND_LIMIT = 5;

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

export type LineDailySendBudget = { ymd: string; count: number; limit: number };

export function readDailySendBudget(
  defaults: Record<string, unknown> | null | undefined,
  ymd: string,
  limit = LINE_DAILY_SEND_LIMIT,
): LineDailySendBudget {
  const raw = defaults?.[BUDGET_KEY];
  if (raw && typeof raw === "object") {
    const o = raw as Record<string, unknown>;
    const storedYmd = String(o.ymd ?? "").trim();
    const count = Number(o.count);
    if (storedYmd === ymd && Number.isFinite(count) && count >= 0) {
      return { ymd, count: Math.floor(count), limit };
    }
  }
  return { ymd, count: 0, limit };
}

export function isDailySendBudgetExhausted(
  defaults: Record<string, unknown> | null | undefined,
  ymd: string,
  limit = LINE_DAILY_SEND_LIMIT,
): boolean {
  return readDailySendBudget(defaults, ymd, limit).count >= limit;
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
  limit = LINE_DAILY_SEND_LIMIT,
): Promise<LineDailySendBudget> {
  const { data, error } = await admin
    .from("app_settings")
    .select("app_defaults")
    .eq("id", "default")
    .maybeSingle();
  if (error) throw error;
  const defaults = (data?.app_defaults ?? {}) as Record<string, unknown>;
  const prev = readDailySendBudget(defaults, ymd, limit);
  const next: LineDailySendBudget = {
    ymd,
    count: prev.count + 1,
    limit,
  };
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
