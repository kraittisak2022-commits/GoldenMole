/**
 * สรุปเช็คชื่อประจำวัน (คนขับรถ + ท่าทราย) → LINE
 * ครอนชั่วโมงละครั้ง 09:00–18:00 Asia/Bangkok
 * - ยังไม่มีข้อมูล → ไม่ส่ง รอรอบถัดไป
 * - มีรายชื่อใหม่/เปลี่ยน → ส่งอัปเดต
 *
 * Auth: header `x-cm-notify-advance-secret` = NOTIFY_ADVANCE_INVOKER_SECRET
 * Body: { "date": "YYYY-MM-DD", "force": true, "testPersonalOnly": true }
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

const DIGEST_KEY = "lineDailyAttendanceDigest";

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
  isUpdate?: boolean;
}): string {
  const dateLine = `${formatDateThaiBE(args.dateYmd)} (${args.dateYmd})`;
  if (args.isUpdate) {
    const lines = [
      "━━━━ GoldenMole ━━━━",
      `อัปเดตเช็คชื่อ ${dateLine} (รายการใหม่)`,
    ];
    if (args.presentIds.length > 0) {
      lines.push(
        `มาทำงานเพิ่ม : ${args.presentIds.length} คน`,
        joinNames(args.presentIds, args.nameById),
      );
    }
    if (args.leaveIds.length > 0) {
      if (args.presentIds.length > 0) lines.push("");
      lines.push(
        `ลางานเพิ่ม : ${args.leaveIds.length} คน`,
        joinNames(args.leaveIds, args.nameById),
      );
    }
    return lines.join("\n").trim();
  }
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
  const saved = readDigestState(defaults, DIGEST_KEY);

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
      hint_th:
        "ยังไม่มีเช็คชื่อวันนี้ — ไม่ส่ง LINE รออัปเดตรอบชั่วโมงถัดไป",
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

  const presentKeys = present.map((id) => `p:${id}`);
  const leaveKeys = leave.map((id) => `l:${id}`);
  const allKeys = [...presentKeys, ...leaveKeys];
  const fingerprint = fingerprintParts([dateYmd, title, ...[...allKeys].sort()]);
  const forceFull = force || testPersonalOnly;
  const newKeys = forceFull ? allKeys : onlyNewKeys(allKeys, saved, dateYmd);
  const newKeySet = new Set(newKeys);
  const presentNew = forceFull
    ? present
    : present.filter((id) => newKeySet.has(`p:${id}`));
  const leaveNew = forceFull
    ? leave
    : leave.filter((id) => newKeySet.has(`l:${id}`));

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
    (presentNew.length === 0 && leaveNew.length === 0)
  ) {
    return jsonResponse({
      ok: true,
      skipped: true,
      code: "unchanged",
      date: dateYmd,
      fingerprint,
      present: present.length,
      leave: leave.length,
      newItems: newKeys.length,
      hint_th: "ไม่มีรายชื่อเช็คชื่อใหม่ — ไม่ส่งซ้ำของเก่า",
    });
  }

  const allIds = uniq([...presentNew, ...leaveNew]);
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

  const isUpdate = decision === "send_update";
  const text = buildAttendanceText({
    dateYmd,
    title,
    presentIds: presentNew,
    leaveIds: leaveNew,
    nameById,
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
    title,
    present: present.length,
    leave: leave.length,
    presentNew: presentNew.length,
    leaveNew: leaveNew.length,
    sand: { present: sandP.length, leave: sandL.length },
    drivers: { present: drvP.length, leave: drvL.length },
    recipients: recipients.length,
    testPersonalOnly,
    notify: notifyJson,
    text,
  });
});
