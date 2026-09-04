/**
 * สรุปเช็คชื่อประจำวัน (คนขับรถ + ท่าทราย) → LINE
 * เรียกด้วย cron 09:00 Asia/Bangkok (02:00 UTC) หรือ POST เอง
 *
 * Auth: header `x-cm-notify-advance-secret` = NOTIFY_ADVANCE_INVOKER_SECRET
 * Body (optional): { "date": "YYYY-MM-DD", "force": true, "testPersonalOnly": true }
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

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

function canonicalLineRecipientId(raw: string): string | null {
  const s = raw.trim();
  const m = s.match(/^([UCR])([a-f0-9]{32})$/i);
  if (!m) return null;
  return `${m[1].toUpperCase()}${m[2].toLowerCase()}`;
}

function parseRecipientIds(raw: string, personalOnly: boolean): string[] {
  const all = [
    ...new Set(
      raw
        .split(/[,;\s]+/)
        .map((x) => canonicalLineRecipientId(x))
        .filter((x): x is string => !!x),
    ),
  ];
  if (personalOnly) return all.filter((id) => id.startsWith("U"));
  return all;
}

function empIdsFromRow(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return [
    ...new Set(
      raw.map((x) => String(x ?? "").trim()).filter(Boolean),
    ),
  ];
}

function stripRecorder(desc: string): string {
  return desc.replace(/\s*\(ผู้กรอก:[^)]+\)\s*$/u, "").trim();
}

function isSandAttendance(desc: string, leaveReason: string): boolean {
  const d = desc + " " + leaveReason;
  return d.includes("ท่าทราย");
}

function isDriverAttendance(desc: string, leaveReason: string): boolean {
  const d = desc + " " + leaveReason;
  return d.includes("คนขับรถ");
}

function joinNames(
  ids: string[],
  nameById: Record<string, string>,
): string {
  if (ids.length === 0) return "—";
  return ids.map((id) => nameById[id] || id).join(", ");
}

function buildAttendanceText(args: {
  dateYmd: string;
  title: string;
  presentIds: string[];
  leaveIds: string[];
  nameById: Record<string, string>;
}): string {
  const dateLine = `${formatDateThaiBE(args.dateYmd)} (${args.dateYmd})`;
  const lines = [
    "━━━━ GoldenMole ━━━━",
    `วันที่ : ${dateLine}`,
    `เช็คชื่อ · ${args.title}`,
    `มาทำงาน :${args.presentIds.length} คน`,
    "",
    "รายชื่อมาทำงาน :",
    joinNames(args.presentIds, args.nameById),
    "",
    `ลางาน : ${args.leaveIds.length} คน`,
    `รายชื่อลางาน : ${joinNames(args.leaveIds, args.nameById)}`,
  ];
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
    .select("app_defaults")
    .eq("id", "default")
    .maybeSingle();
  const defaults =
    settingsRow?.app_defaults && typeof settingsRow.app_defaults === "object"
      ? { ...(settingsRow.app_defaults as Record<string, unknown>) }
      : {};
  const lastSent = String(defaults.lineDailyAttendanceLastYmd ?? "").trim();
  if (!force && !testPersonalOnly && lastSent === dateYmd) {
    return jsonResponse({
      ok: true,
      skipped: true,
      code: "already_sent",
      date: dateYmd,
      hint_th: "ส่งเช็คชื่อวันนี้ไปแล้ว — ส่ง force:true ถ้าต้องการซ้ำ",
    });
  }

  const { data: rows, error } = await admin
    .from("transactions")
    .select(
      "id,category,type,sub_category,labor_status,employee_ids,description,leave_reason",
    )
    .eq("date", dateYmd)
    .or("category.eq.Labor,category.eq.Leave,type.eq.Leave");

  if (error) {
    return jsonResponse({
      ok: false,
      code: "db_error",
      message: error.message,
    });
  }

  const sandPresent: string[] = [];
  const sandLeave: string[] = [];
  const drvPresent: string[] = [];
  const drvLeave: string[] = [];

  for (const t of rows ?? []) {
    const desc = stripRecorder(String(t.description ?? ""));
    const reason = String(t.leave_reason ?? "").trim();
    const ids = empIdsFromRow(t.employee_ids);
    if (ids.length === 0) continue;

    const cat = String(t.category ?? "");
    const sub = String(t.sub_category ?? "").trim();
    const ls = String(t.labor_status ?? "").trim().toLowerCase();
    const isLeave =
      cat === "Leave" ||
      String(t.type ?? "").toLowerCase() === "leave" ||
      ls === "leave" ||
      ls === "sick" ||
      ls === "personal";
    const isAttendanceWork =
      cat === "Labor" && sub === "Attendance" && !isLeave;

    if (isAttendanceWork) {
      if (isDriverAttendance(desc, reason)) drvPresent.push(...ids);
      else if (isSandAttendance(desc, reason)) sandPresent.push(...ids);
      else if (desc.includes("เช็คชื่อ")) {
        // legacy รวม — นับเป็นท่าทรายถ้าไม่ระบุคนขับ
        sandPresent.push(...ids);
      }
      continue;
    }

    if (isLeave && (desc.includes("เช็คชื่อ") || reason.includes("เช็คชื่อ"))) {
      if (isDriverAttendance(desc, reason)) drvLeave.push(...ids);
      else if (isSandAttendance(desc, reason)) sandLeave.push(...ids);
      else sandLeave.push(...ids); // legacy
    }
  }

  const uniq = (xs: string[]) => [...new Set(xs)];
  const sandP = uniq(sandPresent);
  const sandL = uniq(sandLeave);
  const drvP = uniq(drvPresent);
  const drvL = uniq(drvLeave);

  const hasSand = sandP.length > 0 || sandL.length > 0;
  const hasDrv = drvP.length > 0 || drvL.length > 0;
  if (!hasSand && !hasDrv) {
    return jsonResponse({
      ok: true,
      skipped: true,
      code: "no_data",
      date: dateYmd,
      hint_th: "ยังไม่มีเช็คชื่อวันนี้ — ไม่ส่ง LINE",
    });
  }

  let title: string;
  let present: string[];
  let leave: string[];
  if (hasSand && hasDrv) {
    title = "คนขับรถ และ พนักงานท่าทราย";
    present = [...drvP, ...sandP];
    leave = [...drvL, ...sandL];
  } else if (hasDrv) {
    title = "คนขับรถ";
    present = drvP;
    leave = drvL;
  } else {
    title = "พนักงานท่าทราย";
    present = sandP;
    leave = sandL;
  }

  const allIds = uniq([...present, ...leave]);
  const nameById: Record<string, string> = {};
  if (allIds.length > 0) {
    const { data: emps } = await admin
      .from("employees")
      .select("id,name,nickname")
      .in("id", allIds);
    for (const e of emps ?? []) {
      const nick = String(e.nickname ?? "").trim();
      const name = String(e.name ?? "").trim();
      nameById[e.id] = nick || name || e.id;
    }
  }

  const text = buildAttendanceText({
    dateYmd,
    title,
    presentIds: present,
    leaveIds: leave,
    nameById,
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
        : "LINE_ADVANCE_NOTIFY_USER_IDS empty",
      text,
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
    defaults.lineDailyAttendanceLastYmd = dateYmd;
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
    title,
    present: present.length,
    leave: leave.length,
    sand: { present: sandP.length, leave: sandL.length },
    drivers: { present: drvP.length, leave: drvL.length },
    recipients: recipients.length,
    testPersonalOnly,
    notify: notifyJson,
    text,
  });
});
