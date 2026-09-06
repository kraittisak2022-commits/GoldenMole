/**
 * สรุปน้ำมันคงเหลือ (ถังหลัก + ถังสำรอง) → LINE
 * ครอนชั่วโมงละครั้ง 09:00–18:00 Asia/Bangkok
 * - ยอดไม่เปลี่ยนจากรอบก่อน → ไม่ส่ง
 * - มีการเติม/เบิกจนยอดเปลี่ยน → ส่งอัปเดต
 *
 * Auth: header `x-cm-notify-advance-secret` = NOTIFY_ADVANCE_INVOKER_SECRET
 * Body: { "date": "YYYY-MM-DD", "force": true, "testPersonalOnly": true }
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";
import {
  FUEL_STOCK_CUTOVER_YMD,
  buildDailyFuelStockLineText,
  computeFuelStockBalances,
  type FuelTx,
} from "../_shared/fuel_stock_balance.ts";
import {
  digestSendDecision,
  fingerprintParts,
  onlyNewKeys,
  persistDigestState,
  readDigestState,
  unionSentKeys,
} from "../_shared/line_hourly_digest.ts";
import {
  parseGroupReportRecipientIds,
  parseQaUserIds,
  resolveLineAdvanceNotifyIdsCsv,
} from "../_shared/line_recipients.ts";

const DIGEST_KEY = "lineDailyFuelStockDigest";

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
  const saved = readDigestState(defaults, DIGEST_KEY);

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
        "id,date,category,type,sub_category,quantity,unit,fuel_type,fuel_tank,fuel_movement,vehicle_id,vehicle_name,work_type,created_at",
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

  const txsTodayRows = (txs as Array<FuelTx & { id?: string; created_at?: string }>)
    .filter((t) => String(t.date ?? "").slice(0, 10) === dateYmd);
  const txsToday = txsTodayRows.length;
  const mainTotal = bal.mainDiesel + bal.mainBenzine;
  const reserveTotal = bal.reserveDiesel + bal.reserveBenzine;
  if (!force && !testPersonalOnly && txsToday === 0 && mainTotal === 0 &&
    reserveTotal === 0) {
    return jsonResponse({
      ok: true,
      skipped: true,
      code: "no_data",
      date: dateYmd,
      hint_th:
        "ยังไม่มียอดน้ำมัน/รายการวันนี้ — ไม่ส่ง LINE รออัปเดตรอบชั่วโมงถัดไป",
      balance: bal,
    });
  }

  const todayKeys = txsTodayRows.map((t) => {
    const id = String(t.id ?? "").trim();
    if (id) return `fuel:${id}`;
    return `fuel:${t.created_at}|${t.sub_category}|${t.quantity}|${t.fuel_tank}`;
  });
  const fingerprint = fingerprintParts([
    dateYmd,
    Math.round(bal.mainDiesel * 100),
    Math.round(bal.reserveDiesel * 100),
    Math.round(bal.mainBenzine * 100),
    Math.round(bal.reserveBenzine * 100),
    ...[...todayKeys].sort(),
  ]);

  const forceFull = force || testPersonalOnly;
  const newKeys = forceFull
    ? todayKeys
    : onlyNewKeys(todayKeys, saved, dateYmd);

  const decision = digestSendDecision({
    force,
    testPersonalOnly,
    dateYmd,
    fingerprint,
    saved,
    newItemCount: newKeys.length,
  });
  if (decision === "skip_unchanged") {
    return jsonResponse({
      ok: true,
      skipped: true,
      code: "unchanged",
      date: dateYmd,
      fingerprint,
      balance: bal,
      hint_th: "รายงานน้ำมันวันนี้ส่งแล้ว และไม่มีรายการใหม่ — ไม่ส่งซ้ำ",
    });
  }

  const isUpdate = decision === "send_update";
  let text: string;
  if (!isUpdate || forceFull) {
    text = buildDailyFuelStockLineText(dateYmd, bal, formatDateThaiBE);
  } else {
    const newKeySet = new Set(newKeys);
    const newRows = txsTodayRows.filter((t, i) => newKeySet.has(todayKeys[i]));
    if (newRows.length === 0) {
      return jsonResponse({
        ok: true,
        skipped: true,
        code: "unchanged",
        date: dateYmd,
        hint_th: "ไม่มีรายการน้ำมันใหม่ — ไม่ส่งซ้ำ",
      });
    }
    const lines = [
      `อัปเดตน้ำมัน ${formatDateThaiBE(dateYmd)} (รายการใหม่)`,
      "",
    ];
    for (const r of newRows) {
      const qty = Number(r.quantity);
      const q = Number.isFinite(qty) ? `${qty} ${r.unit || "L"}` : "—";
      lines.push(
        `${r.fuel_movement || r.sub_category || "—"} · ${r.fuel_type || "—"} · ถัง ${r.fuel_tank || "—"} · ${q}` +
          (r.vehicle_name ? ` · ${r.vehicle_name}` : ""),
      );
    }
    lines.push(
      "",
      `ยอดล่าสุด ถังหลัก : ${Math.round(mainTotal).toLocaleString("th-TH")} ลิตร`,
      `ถังสำรอง : ${Math.round(reserveTotal).toLocaleString("th-TH")} ลิตร`,
    );
    text = lines.join("\n").trim();
  }

  const recipients = parseRecipientIds(
    await resolveLineAdvanceNotifyIdsCsv(admin),
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
    // รอบแรกไม่มี fuel tx ก็จำว่าส่งแล้วด้วย sentinel
    const sentKeys = forceFull || decision === "send_first"
      ? (todayKeys.length > 0 ? todayKeys : [`fuel:balance:${dateYmd}`])
      : newKeys;
    await persistDigestState(admin, DIGEST_KEY, {
      ymd: dateYmd,
      fingerprint,
      items: unionSentKeys(saved, dateYmd, sentKeys),
    });
  }

  return jsonResponse({
    ok: true,
    date: dateYmd,
    update: isUpdate,
    fingerprint,
    balance: bal,
    newFuelRows: isUpdate && !forceFull ? newKeys.length : txsToday,
    recipients: recipients.length,
    testPersonalOnly,
    notify: notifyJson,
    text,
  });
});
