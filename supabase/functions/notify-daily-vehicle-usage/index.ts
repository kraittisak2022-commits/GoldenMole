/**
 * สรุปการใช้รถดรัม + แม็คโคร ประจำวัน → LINE
 * เรียกด้วย cron 09:00 Asia/Bangkok (02:00 UTC) หรือ POST เอง
 *
 * Auth: header `x-cm-notify-advance-secret` = NOTIFY_ADVANCE_INVOKER_SECRET
 * Secrets: LINE_CHANNEL_ACCESS_TOKEN, LINE_ADVANCE_NOTIFY_USER_IDS,
 *          NOTIFY_ADVANCE_INVOKER_SECRET
 *
 * Body (optional): { "date": "YYYY-MM-DD", "force": true, "testPersonalOnly": true }
 *   force=true — ส่งซ้ำแม้เคยส่งวันนั้นแล้ว
 *   รายงานปกติส่งเข้ากลุ่ม (C…/R…) เท่านั้น
 *   testPersonalOnly — ส่งเฉพาะ User ID (U…) ตอนทดสอบ
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";
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
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Bangkok",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  return fmt.format(d); // YYYY-MM-DD
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

function isMacroVehicleName(raw: string): boolean {
  const s = raw.trim().toLowerCase();
  if (!s) return false;
  return (
    s.includes("แม็คโคร") ||
    s.includes("แมคโคร") ||
    s.includes("excavator") ||
    s.includes("backhoe")
  );
}

function vehicleLabel(row: {
  vehicle_name?: string | null;
  vehicle_id?: string | null;
}): string {
  const name = (row.vehicle_name ?? "").trim();
  if (name) return name;
  return (row.vehicle_id ?? "").trim() || "—";
}

function parseRecipientIds(raw: string, personalOnly = false): string[] {
  // รายงานปกติ = กลุ่มเท่านั้น; testPersonalOnly = แชทส่วนตัวตอนทดสอบ
  if (personalOnly) return parseQaUserIds(raw);
  return parseGroupReportRecipientIds(raw);
}

function empDisplayName(e: {
  id: string;
  name?: string | null;
  nickname?: string | null;
}): string {
  const nick = (e.nickname ?? "").trim();
  if (nick) return nick;
  const name = (e.name ?? "").trim();
  if (name) return name;
  return e.id;
}

function buildDailyVehicleUsageText(args: {
  dateYmd: string;
  drums: { vehicle: string; driverName: string }[];
  macros: { vehicle: string; driverName: string; work: string }[];
}): string {
  const lines: string[] = [
    `การใช้รถ ${formatDateThaiBE(args.dateYmd)}`,
    "",
    `บันทึกรถดรัม จำนวน ${args.drums.length} คัน`,
  ];
  args.drums.forEach((it, i) => {
    lines.push(`คันที่ ${i + 1} : ${it.vehicle} · ${it.driverName}`);
  });
  lines.push("", `รถแม็คโคร จำนวน ${args.macros.length} คัน`);
  args.macros.forEach((it, i) => {
    lines.push(
      `คันที่ ${i + 1} : ${it.vehicle} · ${it.driverName} · ${it.work}`,
    );
  });
  return lines.join("\n").trim();
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

  let body: { date?: string; force?: boolean; testPersonalOnly?: boolean } = {};
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

  // idempotency — กันส่งซ้ำในวันเดียวกัน (ยกเว้น force)
  const { data: settingsRow } = await admin
    .from("app_settings")
    .select("app_defaults")
    .eq("id", "default")
    .maybeSingle();
  const defaults =
    settingsRow?.app_defaults && typeof settingsRow.app_defaults === "object"
      ? { ...(settingsRow.app_defaults as Record<string, unknown>) }
      : {};
  const lastSent = String(defaults.lineDailyVehicleUsageLastYmd ?? "").trim();
  if (!force && !testPersonalOnly && lastSent === dateYmd) {
    return jsonResponse({
      ok: true,
      skipped: true,
      code: "already_sent",
      date: dateYmd,
      hint_th: "ส่งสรุปการใช้รถวันนี้ไปแล้ว — ส่ง force:true ถ้าต้องการซ้ำ",
    });
  }

  const [tripsRes, vehRes] = await Promise.all([
    admin
      .from("transactions")
      .select("vehicle_id,vehicle_name,driver_id,created_at")
      .eq("date", dateYmd)
      .eq("category", "DailyLog")
      .eq("sub_category", "VehicleTrip")
      .order("created_at", { ascending: true }),
    admin
      .from("transactions")
      .select(
        "vehicle_id,vehicle_name,driver_id,work_details,description,created_at",
      )
      .eq("date", dateYmd)
      .eq("category", "Vehicle")
      .order("created_at", { ascending: true }),
  ]);

  if (tripsRes.error || vehRes.error) {
    return jsonResponse({
      ok: false,
      code: "db_error",
      tripsError: tripsRes.error?.message,
      vehicleError: vehRes.error?.message,
    });
  }

  const trips = tripsRes.data ?? [];
  const macros = (vehRes.data ?? []).filter((t) =>
    isMacroVehicleName(vehicleLabel(t))
  );

  if (trips.length === 0 && macros.length === 0) {
    return jsonResponse({
      ok: true,
      skipped: true,
      code: "no_data",
      date: dateYmd,
      hint_th: "ยังไม่มีบันทึกรถดรัมหรือแม็คโครวันนี้ — ไม่ส่ง LINE",
    });
  }

  const driverIds = [
    ...new Set(
      [...trips, ...macros]
        .map((t) => (t.driver_id ?? "").trim())
        .filter(Boolean),
    ),
  ];
  const nameById: Record<string, string> = {};
  if (driverIds.length > 0) {
    const { data: emps } = await admin
      .from("employees")
      .select("id,name,nickname")
      .in("id", driverIds);
    for (const e of emps ?? []) {
      nameById[e.id] = empDisplayName(e);
    }
  }

  const drums = trips.map((t) => ({
    vehicle: vehicleLabel(t),
    driverName: nameById[(t.driver_id ?? "").trim()] ||
      (t.driver_id ?? "").trim() ||
      "—",
  }));
  const macroItems = macros.map((t) => ({
    vehicle: vehicleLabel(t),
    driverName: nameById[(t.driver_id ?? "").trim()] ||
      (t.driver_id ?? "").trim() ||
      "—",
    work: ((t.work_details ?? "").trim() || "—"),
  }));

  const text = buildDailyVehicleUsageText({
    dateYmd,
    drums,
    macros: macroItems,
  });

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
      textPreview: text.slice(0, 200),
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
    });
  }

  if (!testPersonalOnly) {
    defaults.lineDailyVehicleUsageLastYmd = dateYmd;
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
    drums: drums.length,
    macros: macroItems.length,
    recipients: recipients.length,
    testPersonalOnly,
    notify: notifyJson,
    text,
  });
});
