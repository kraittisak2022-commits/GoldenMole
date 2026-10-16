/**
 * Daily system posts for the "อัพเดตงาน" feed:
 * - Leave digest (upsert on leave:YYYY-MM-DD)
 * - One task_nag post per unfinished shared/assigned task whose due_date ≤ today
 *   (dedupe: nag:<taskId>:YYYY-MM-DD)
 *
 * Cron: 07:30 / 13:00 Asia/Bangkok (00:30 / 06:00 UTC)
 * Auth: header `x-cm-notify-advance-secret` = NOTIFY_ADVANCE_INVOKER_SECRET
 * Body: { "date": "YYYY-MM-DD", "force": true }
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

function empIdsFromRow(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return [
    ...new Set(
      raw.map((x) => String(x ?? "").trim()).filter(Boolean),
    ),
  ];
}

function addDaysYmd(ymd: string, days: number): string {
  const [y, m, d] = ymd.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + days));
  return dt.toISOString().slice(0, 10);
}

function daysBetween(a: string, b: string): number {
  const [ay, am, ad] = a.split("-").map(Number);
  const [by, bm, bd] = b.split("-").map(Number);
  const ms =
    Date.UTC(by, bm - 1, bd) - Date.UTC(ay, am - 1, ad);
  return Math.floor(ms / 86_400_000);
}

function isLeaveRow(t: {
  category?: string | null;
  type?: string | null;
  labor_status?: string | null;
}): boolean {
  const cat = String(t.category ?? "");
  const ls = String(t.labor_status ?? "").trim().toLowerCase();
  return (
    cat === "Leave" ||
    String(t.type ?? "").toLowerCase() === "leave" ||
    ls === "leave" ||
    ls === "sick" ||
    ls === "personal"
  );
}

function leaveKind(t: {
  sub_category?: string | null;
  labor_status?: string | null;
}): string {
  const sub = String(t.sub_category ?? "").toLowerCase();
  const ls = String(t.labor_status ?? "").toLowerCase();
  if (sub.includes("sick") || ls === "sick") return "sick";
  if (sub.includes("personal") || ls === "personal") return "personal";
  return "leave";
}

function leaveKindLabel(kind: string): string {
  switch (kind) {
    case "sick":
      return "ลาป่วย";
    case "personal":
      return "ลากิจ";
    default:
      return "ลางาน";
  }
}

function leaveCoversDay(
  startYmd: string,
  leaveDays: number,
  day: string,
): boolean {
  const span = Math.max(1, Math.ceil(Number(leaveDays) || 1));
  const end = addDaysYmd(startYmd, span - 1);
  return day >= startYmd && day <= end;
}

function isHalfDay(leaveDays: number, workDetails: unknown): boolean {
  if (Number(leaveDays) > 0 && Number(leaveDays) < 1) return true;
  if (workDetails && typeof workDetails === "object") {
    const wd = workDetails as Record<string, unknown>;
    if (wd.halfDay === true || wd.half === true) return true;
    const part = String(wd.halfPart ?? wd.part ?? "").toLowerCase();
    if (part === "am" || part === "pm" || part === "morning" || part === "afternoon") {
      return true;
    }
  }
  return false;
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

  let body: { date?: string; force?: boolean } = {};
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

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    return jsonResponse({
      ok: false,
      code: "server_misconfigured",
      message: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY",
    });
  }

  const admin = createClient(supabaseUrl, serviceKey);
  const dateLabel = formatDateThaiBE(dateYmd);

  // ── Leave digest ──────────────────────────────────────────────
  // Fetch leave rows that could cover today (started within last 60 days).
  const lookback = addDaysYmd(dateYmd, -60);
  const { data: txRows, error: txErr } = await admin
    .from("transactions")
    .select(
      "id,date,category,type,sub_category,labor_status,employee_ids,leave_days,leave_reason,work_details",
    )
    .gte("date", lookback)
    .lte("date", dateYmd)
    .or("category.eq.Leave,category.eq.Labor,type.eq.Leave");

  if (txErr) {
    return jsonResponse({
      ok: false,
      code: "db_error",
      message: txErr.message,
    });
  }

  const { data: empRows } = await admin
    .from("employees")
    .select("id,name");
  const nameById: Record<string, string> = {};
  for (const e of empRows ?? []) {
    const id = String(e.id ?? "").trim();
    if (id) nameById[id] = String(e.name ?? id).trim() || id;
  }

  type LeaveEntry = {
    employeeId: string;
    name: string;
    kind: string;
    halfDay: boolean;
  };
  const leaveMap = new Map<string, LeaveEntry>();

  for (const t of txRows ?? []) {
    if (!isLeaveRow(t)) continue;
    const start = String(t.date ?? "").slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(start)) continue;
    const leaveDays = Number(t.leave_days) || 1;
    if (!leaveCoversDay(start, leaveDays, dateYmd)) continue;
    const ids = empIdsFromRow(t.employee_ids);
    if (ids.length === 0) continue;
    const kind = leaveKind(t);
    const half = isHalfDay(leaveDays, t.work_details);
    for (const id of ids) {
      if (leaveMap.has(id)) continue;
      leaveMap.set(id, {
        employeeId: id,
        name: nameById[id] || id,
        kind,
        halfDay: half,
      });
    }
  }

  const leaveList = [...leaveMap.values()].sort((a, b) =>
    a.name.localeCompare(b.name, "th")
  );

  let leaveBody: string;
  if (leaveList.length === 0) {
    leaveBody = `วันนี้ทุกคนมาทำงาน\n${dateLabel}`;
  } else {
    const lines = leaveList.map((e) => {
      const tag = leaveKindLabel(e.kind);
      const half = e.halfDay ? " · ครึ่งวัน" : "";
      return `• ${e.name} (${tag}${half})`;
    });
    leaveBody = [
      `วันนี้มีคนลา ${leaveList.length} คน`,
      dateLabel,
      "",
      ...lines,
    ].join("\n");
  }

  const leaveDedupe = `leave:${dateYmd}`;
  const leavePayload = {
    kind: "leave_digest",
    author_admin_id: null,
    author_name: "ระบบ",
    body: leaveBody,
    task_id: null,
    media: [],
    meta: { date: dateYmd, leaves: leaveList },
    dedupe_key: leaveDedupe,
    pinned: false,
    updated_at: new Date().toISOString(),
    deleted_at: null,
  };

  const { data: existingLeave } = await admin
    .from("feed_posts")
    .select("id")
    .eq("dedupe_key", leaveDedupe)
    .is("deleted_at", null)
    .maybeSingle();

  let leaveAction: "inserted" | "updated";
  if (existingLeave?.id) {
    const { error } = await admin
      .from("feed_posts")
      .update({
        body: leavePayload.body,
        meta: leavePayload.meta,
        updated_at: leavePayload.updated_at,
      })
      .eq("id", existingLeave.id);
    if (error) {
      return jsonResponse({
        ok: false,
        code: "db_error",
        message: error.message,
      });
    }
    leaveAction = "updated";
  } else {
    const { error } = await admin.from("feed_posts").insert(leavePayload);
    if (error) {
      // Unique race: treat as ok
      if (!String(error.message).includes("duplicate") && error.code !== "23505") {
        return jsonResponse({
          ok: false,
          code: "db_error",
          message: error.message,
        });
      }
    }
    leaveAction = "inserted";
  }

  // ── Task nag posts ────────────────────────────────────────────
  const { data: tasks, error: taskErr } = await admin
    .from("tasks")
    .select(
      "id,title,note,status,priority,due_date,visibility,assignee_admin_id,assignee_name,owner_admin_id,owner_name",
    )
    .neq("status", "Done")
    .lte("due_date", dateYmd);

  if (taskErr) {
    return jsonResponse({
      ok: false,
      code: "db_error",
      message: taskErr.message,
      leave: { action: leaveAction, count: leaveList.length },
    });
  }

  // Shared (public) or assigned tasks only — skip purely private unassigned ones.
  const nagTargets = (tasks ?? []).filter((t) => {
    const vis = String(t.visibility ?? "public");
    const assignee = String(t.assignee_admin_id ?? "").trim();
    if (vis === "public" || vis === "shared") return true;
    return assignee.length > 0;
  });

  let nagInserted = 0;
  let nagSkipped = 0;

  for (const t of nagTargets) {
    const taskId = String(t.id ?? "").trim();
    if (!taskId) continue;
    const due = String(t.due_date ?? "").slice(0, 10);
    const overdue = Math.max(0, daysBetween(due, dateYmd));
    const assigneeName =
      String(t.assignee_name ?? "").trim() ||
      String(t.owner_name ?? "").trim() ||
      "ยังไม่ระบุ";
    const priority = String(t.priority ?? "Normal");
    const title = String(t.title ?? "").trim() || "งานไม่มีชื่อ";

    const overdueLabel =
      overdue === 0
        ? "ครบกำหนดวันนี้"
        : `ค้างมา ${overdue} วัน`;

    const body = [
      `ทวงงาน: ${title}`,
      overdueLabel,
      `ผู้รับผิดชอบ: ${assigneeName}`,
      `ความสำคัญ: ${priority}`,
    ].join("\n");

    const dedupe = `nag:${taskId}:${dateYmd}`;
    const payload = {
      kind: "task_nag",
      author_admin_id: null,
      author_name: "ระบบ",
      body,
      task_id: taskId,
      media: [],
      meta: {
        date: dateYmd,
        daysOverdue: overdue,
        assigneeName,
        priority,
        title,
        dueDate: due,
      },
      dedupe_key: dedupe,
      pinned: false,
      deleted_at: null,
    };

    const { error } = await admin.from("feed_posts").insert(payload);
    if (error) {
      if (error.code === "23505" || String(error.message).includes("duplicate")) {
        nagSkipped += 1;
      } else {
        console.error("nag insert failed", taskId, error.message);
      }
    } else {
      nagInserted += 1;
    }
  }

  return jsonResponse({
    ok: true,
    date: dateYmd,
    leave: { action: leaveAction, count: leaveList.length },
    nags: {
      candidates: nagTargets.length,
      inserted: nagInserted,
      skippedExisting: nagSkipped,
    },
  });
});
