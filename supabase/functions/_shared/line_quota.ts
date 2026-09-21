/**
 * LINE Messaging API free-plan monthly quota guard.
 * When LINE returns 429 "monthly limit", pause digests until next Bangkok month
 * so hourly cron does not keep hammering a dead quota.
 */
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

const QUOTA_KEY = "lineMessagingQuotaBlockUntil";

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

/** ISO timestamp for 00:00 Asia/Bangkok on the 1st of next month */
export function nextBangkokMonthStartIso(from = new Date()): string {
  const { y, m } = bangkokYmdParts(from);
  const nextY = m === 12 ? y + 1 : y;
  const nextM = m === 12 ? 1 : m + 1;
  const mm = String(nextM).padStart(2, "0");
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

export async function readLineQuotaBlocked(
  admin: SupabaseClient,
): Promise<{ blocked: boolean; until: string | null }> {
  const { data, error } = await admin
    .from("app_settings")
    .select("app_defaults")
    .eq("id", "default")
    .maybeSingle();
  if (error || !data) return { blocked: false, until: null };
  const defaults = (data.app_defaults ?? {}) as Record<string, unknown>;
  const until =
    typeof defaults[QUOTA_KEY] === "string"
      ? String(defaults[QUOTA_KEY])
      : null;
  return {
    blocked: isLineQuotaBlockedFromDefaults(defaults),
    until,
  };
}

export async function markLineQuotaBlocked(
  admin: SupabaseClient,
  untilIso = nextBangkokMonthStartIso(),
): Promise<string> {
  const { error: rpcErr } = await admin.rpc("set_app_defaults_key", {
    p_key: QUOTA_KEY,
    p_value: untilIso,
  });
  if (!rpcErr) return untilIso;

  console.warn("markLineQuotaBlocked RPC failed, fallback upsert", rpcErr.message);
  const { data, error } = await admin
    .from("app_settings")
    .select("app_defaults")
    .eq("id", "default")
    .maybeSingle();
  if (error) throw error;
  const defaults = {
    ...((data?.app_defaults as Record<string, unknown> | null) ?? {}),
    [QUOTA_KEY]: untilIso,
  };
  const { error: upErr } = await admin
    .from("app_settings")
    .upsert({ id: "default", app_defaults: defaults }, { onConflict: "id" });
  if (upErr) throw upErr;
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
