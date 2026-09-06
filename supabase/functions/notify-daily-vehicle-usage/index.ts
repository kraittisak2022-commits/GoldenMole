/**
 * สรุปการใช้รถดรัม + แม็คโคร → LINE
 * ครอนชั่วโมงละครั้ง 09:00–18:00 Asia/Bangkok
 * - ยังไม่มีข้อมูล (0) → ไม่ส่ง รอรอบถัดไป
 * - มีข้อมูลใหม่ → ส่งเฉพาะรายการใหม่ (ไม่ส่งของที่เคยแจ้งแล้วซ้ำ)
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";
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

const DIGEST_KEY = "lineDailyVehicleUsageDigest";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cm-notify-advance-secret",
};

const TH_MONTHS = [
  "ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.",
  "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค.",
];

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
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

type DrumItem = { key: string; vehicle: string; driverName: string };
type MacroItem = {
  key: string;
  vehicle: string;
  driverName: string;
  work: string;
};

function buildVehicleDeltaText(args: {
  dateYmd: string;
  drums: DrumItem[];
  macros: MacroItem[];
  isUpdate: boolean;
}): string {
  const lines: string[] = [
    args.isUpdate
      ? `อัปเดตการใช้รถ ${formatDateThaiBE(args.dateYmd)} (รายการใหม่)`
      : `การใช้รถ ${formatDateThaiBE(args.dateYmd)}`,
    "",
  ];
  if (args.drums.length > 0) {
    lines.push(
      args.isUpdate
        ? `รถดรัมเพิ่ม ${args.drums.length} คัน`
        : `บันทึกรถดรัม จำนวน ${args.drums.length} คัน`,
    );
    args.drums.forEach((it, i) => {
      lines.push(`คันที่ ${i + 1} : ${it.vehicle} · ${it.driverName}`);
    });
  }
  if (args.macros.length > 0) {
    if (args.drums.length > 0) lines.push("");
    lines.push(
      args.isUpdate
        ? `รถแม็คโครเพิ่ม ${args.macros.length} คัน`
        : `รถแม็คโคร จำนวน ${args.macros.length} คัน`,
    );
    args.macros.forEach((it, i) => {
      lines.push(
        `คันที่ ${i + 1} : ${it.vehicle} · ${it.driverName} · ${it.work}`,
      );
    });
  }
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

  const { data: settingsRow } = await admin
    .from("app_settings")
    .select("app_defaults")
    .eq("id", "default")
    .maybeSingle();
  const defaults =
    settingsRow?.app_defaults && typeof settingsRow.app_defaults === "object"
      ? { ...(settingsRow.app_defaults as Record<string, unknown>) }
      : {};

  const [tripsRes, vehRes] = await Promise.all([
    admin
      .from("transactions")
      .select("id,vehicle_id,vehicle_name,driver_id,created_at")
      .eq("date", dateYmd)
      .eq("category", "DailyLog")
      .eq("sub_category", "VehicleTrip")
      .order("created_at", { ascending: true }),
    admin
      .from("transactions")
      .select(
        "id,vehicle_id,vehicle_name,driver_id,work_details,description,created_at",
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
      hint_th:
        "ยังไม่มีบันทึกรถดรัมหรือแม็คโคร — ไม่ส่ง LINE รออัปเดตรอบชั่วโมงถัดไป",
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

  const drumsAll: DrumItem[] = trips.map((t) => {
    const vehicle = vehicleLabel(t);
    const driverName = nameById[(t.driver_id ?? "").trim()] ||
      (t.driver_id ?? "").trim() ||
      "—";
    const id = String(t.id ?? "").trim();
    const key = id
      ? `drum:${id}`
      : `drum:${vehicle}|${driverName}|${t.created_at ?? ""}`;
    return { key, vehicle, driverName };
  });
  const macrosAll: MacroItem[] = macros.map((t) => {
    const vehicle = vehicleLabel(t);
    const driverName = nameById[(t.driver_id ?? "").trim()] ||
      (t.driver_id ?? "").trim() ||
      "—";
    const work = ((t.work_details ?? "").trim() || "—");
    const id = String(t.id ?? "").trim();
    const key = id
      ? `macro:${id}`
      : `macro:${vehicle}|${driverName}|${work}|${t.created_at ?? ""}`;
    return { key, vehicle, driverName, work };
  });

  const allKeys = [...drumsAll.map((d) => d.key), ...macrosAll.map((m) => m.key)];
  const fingerprint = fingerprintParts([dateYmd, ...[...allKeys].sort()]);
  const saved = readDigestState(defaults, DIGEST_KEY);

  const forceFull = force || testPersonalOnly;
  const newKeys = forceFull ? allKeys : onlyNewKeys(allKeys, saved, dateYmd);
  const newKeySet = new Set(newKeys);
  const drums = forceFull ? drumsAll : drumsAll.filter((d) => newKeySet.has(d.key));
  const macroItems = forceFull
    ? macrosAll
    : macrosAll.filter((m) => newKeySet.has(m.key));

  const decision = digestSendDecision({
    force,
    testPersonalOnly,
    dateYmd,
    fingerprint,
    saved,
    newItemCount: newKeys.length,
  });
  if (
    decision === "skip_unchanged" ||
    (drums.length === 0 && macroItems.length === 0)
  ) {
    return jsonResponse({
      ok: true,
      skipped: true,
      code: "unchanged",
      date: dateYmd,
      fingerprint,
      drums: drumsAll.length,
      macros: macrosAll.length,
      newItems: newKeys.length,
      hint_th: "ไม่มีรายการรถใหม่จากรอบที่ส่งแล้ว — ไม่ส่งซ้ำของเก่า",
    });
  }

  const isUpdate = decision === "send_update";
  const text = buildVehicleDeltaText({
    dateYmd,
    drums,
    macros: macroItems,
    isUpdate,
  });

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
    await persistDigestState(admin, DIGEST_KEY, {
      ymd: dateYmd,
      fingerprint,
      items: unionSentKeys(saved, dateYmd, newKeys),
    });
  }

  return jsonResponse({
    ok: true,
    date: dateYmd,
    update: isUpdate,
    fingerprint,
    drumsTotal: drumsAll.length,
    macrosTotal: macrosAll.length,
    drumsNew: drums.length,
    macrosNew: macroItems.length,
    recipients: recipients.length,
    testPersonalOnly,
    notify: notifyJson,
    text,
  });
});
