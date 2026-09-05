/**
 * สรุปน้ำมันคงเหลือ (ถังหลัก + ถังสำรอง) → LINE
 * เรียกด้วย cron 09:00 Asia/Bangkok (02:00 UTC) หรือ POST เอง
 *
 * Auth: header `x-cm-notify-advance-secret` = NOTIFY_ADVANCE_INVOKER_SECRET
 * Body (optional): { "date": "YYYY-MM-DD", "force": true, "testPersonalOnly": true }
 *   รายงานปกติส่งเข้ากลุ่ม (C…/R…) เท่านั้น
 *   testPersonalOnly — ส่งเฉพาะ User ID (U…) ตอนทดสอบ
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";
import {
  FUEL_STOCK_CUTOVER_YMD,
  buildDailyFuelStockLineText,
  computeFuelStockBalances,
  type FuelTx,
} from "../_shared/fuel_stock_balance.ts";
import {
  parseGroupReportRecipientIds,
  parseQaUserIds,
} from "../_shared/line_recipients.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cm-notify-advance-secret",
};

const TH_MONTHS = [
  "ม.ค.",
  "ก.พ.",
  "มี.ค.",
  "เม.ย.",
  "พ.ค.",
  "มิ.ย.",
  "ก.ค.",
  "ส.ค.",
  "ก.ย.",
  "ต.ค.",
  "พ.ย.",
  "ธ.ค.",
];

function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function secureCompareStrings(a: string, b: string): boolean {
  const x = a.trim();
  const y = b.trim();
  if (!x || !y || x.length !== y.length) return false;
  let d = 0;
  for (let i = 0; i < x.length; i++) d |= x.charCodeAt(i) ^ y.charCodeAt(i);
  return d === 0;
}

function bangkokYmd(d = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Bangkok",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}

function formatDateThaiBE(ymd: string): string {
  const segs = ymd.split("-");
  if (segs.length !== 3) return ymd;
  const y = Number(segs[0]);
  const m = Number(segs[1]);
  const d = Number(segs[2]);
  if (!y || m < 1 || m > 12 || !d) return ymd;
  return `${d} ${TH_MONTHS[m - 1]} ${y + 543}`;
}

function parseRecipientIds(raw: string, personalOnly: boolean): string[] {
  if (personalOnly) return parseQaUserIds(raw);
  return parseGroupReportRecipientIds(raw);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: corsHeaders,
    });
  }

  const envSecret = (Deno.env.get("NOTIFY_ADVANCE_INVOKER_SECRET") ?? "").trim();
  const headerSecret = (req.headers.get("x-cm-notify-advance-secret") ?? "")
    .trim();
  if (
    !envSecret ||
    !headerSecret ||
    !secureCompareStrings(envSecret, headerSecret)
  ) {
    return jsonResponse(
      {
        ok: false,
        error: "Unauthorized",
        hint_th:
          "ส่ง header x-cm-notify-advance-secret ให้ตรงกับ NOTIFY_ADVANCE_INVOKER_SECRET",
      },
      401,
    );
  }

  let body: {
    date?: string;
    force?: boolean;
    testPersonalOnly?: boolean;
  } = {};
  try {
    const raw = await req.text();
    if (raw.trim()) body = JSON.parse(raw);
  } catch {
    return jsonResponse({
      ok: false,
      code: "invalid_json",
      message: "Invalid JSON",
    });
  }

  const dateYmd =
    typeof body.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(body.date.trim())
      ? body.date.trim()
      : bangkokYmd();
  const force = body.force === true;
  const testPersonalOnly = body.testPersonalOnly === true;

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    return jsonResponse({
      ok: false,
      code: "server_misconfigured",
      message: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY",
    });
  }

  const admin = createClient(supabaseUrl, serviceKey);

  const { data: settingsRow } = await admin
    .from("app_settings")
    .select("app_defaults, fuel_opening_stock")
    .eq("id", "default")
    .maybeSingle();

  const defaults =
    settingsRow?.app_defaults && typeof settingsRow.app_defaults === "object"
      ? { ...(settingsRow.app_defaults as Record<string, unknown>) }
      : {};
  const lastSent = String(defaults.lineDailyFuelStockLastYmd ?? "").trim();
  if (!force && !testPersonalOnly && lastSent === dateYmd) {
    return jsonResponse({
      ok: true,
      skipped: true,
      code: "already_sent",
      date: dateYmd,
      hint_th: "ส่งน้ำมันคงเหลือวันนี้ไปแล้ว — ส่ง force:true ถ้าต้องการซ้ำ",
    });
  }

  const openingRaw = settingsRow?.fuel_opening_stock;
  const opening =
    openingRaw && typeof openingRaw === "object"
      ? (openingRaw as Record<string, unknown>)
      : {};
  const num = (v: unknown) => {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  };

  // ดึงรายการ Fuel ตั้งแต่วันตัดยอด (paginate)
  const pageSize = 1000;
  const txs: FuelTx[] = [];
  for (let from = 0; ; from += pageSize) {
    const to = from + pageSize - 1;
    const { data, error } = await admin
      .from("transactions")
      .select(
        "date,category,type,sub_category,quantity,unit,fuel_type,fuel_tank,fuel_movement,vehicle_id,vehicle_name,work_type",
      )
      .eq("category", "Fuel")
      .gte("date", FUEL_STOCK_CUTOVER_YMD)
      .lte("date", dateYmd)
      .order("date", { ascending: true })
      .range(from, to);
    if (error) {
      return jsonResponse({
        ok: false,
        code: "db_error",
        message: error.message,
      });
    }
    const chunk = (data ?? []) as FuelTx[];
    txs.push(...chunk);
    if (chunk.length < pageSize) break;
  }

  const bal = computeFuelStockBalances(txs, {
    Diesel: num(opening.Diesel),
    Benzine: num(opening.Benzine),
    DieselReserve: num(opening.DieselReserve),
    BenzineReserve: num(opening.BenzineReserve),
    asOfYmd: dateYmd,
  });

  const text = buildDailyFuelStockLineText(dateYmd, bal, formatDateThaiBE);

  const recipients = parseRecipientIds(
    Deno.env.get("LINE_ADVANCE_NOTIFY_USER_IDS") ?? "",
    testPersonalOnly,
  );
  if (recipients.length === 0) {
    return jsonResponse({
      ok: false,
      code: "no_recipients",
      message: testPersonalOnly
        ? "No personal U… recipients"
        : "ไม่มี Group/Room ID ใน LINE_ADVANCE_NOTIFY_USER_IDS (รายงานส่งเข้ากลุ่มเท่านั้น)",
      text,
      balance: bal,
    });
  }

  const notifyUrl = `${supabaseUrl}/functions/v1/notify-advance-line`;
  const notifyRes = await fetch(notifyUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${anonKey || serviceKey}`,
      "Content-Type": "application/json",
      "x-cm-notify-advance-secret": envSecret,
    },
    body: JSON.stringify({ text, to: recipients }),
  });
  const notifyJson = await notifyRes.json().catch(() => ({}));

  if (!notifyJson || notifyJson.ok !== true) {
    return jsonResponse({
      ok: false,
      code: "line_send_failed",
      date: dateYmd,
      notify: notifyJson,
      text,
      balance: bal,
    });
  }

  if (!testPersonalOnly) {
    defaults.lineDailyFuelStockLastYmd = dateYmd;
    await admin
      .from("app_settings")
      .upsert(
        { id: "default", app_defaults: defaults },
        { onConflict: "id" },
      );
  }

  return jsonResponse({
    ok: true,
    date: dateYmd,
    balance: bal,
    recipients: recipients.length,
    testPersonalOnly,
    notify: notifyJson,
    text,
  });
});
