/**
 * Read-only DB tools for LINE personal QA (same Supabase data as the web app).
 */
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";
import {
  bangkokYmd,
  buildAttendanceReportText,
  buildFuelReportText,
  buildVehicleReportText,
  formatDateThaiBE,
} from "./line_qa_reports.ts";

export type QaToolDef = {
  type: "function";
  function: {
    name: string;
    description: string;
    parameters: Record<string, unknown>;
  };
};

const dateProp = {
  type: "string",
  description: "วันที่ YYYY-MM-DD (Asia/Bangkok) ถ้าไม่ระบุใช้วันนี้",
};

export const LINE_QA_TOOLS: QaToolDef[] = [
  {
    type: "function",
    function: {
      name: "get_ops_snapshot",
      description:
        "สรุปภาพรวมวันนี้: น้ำมันคงเหลือ + เช็คชื่อ + การใช้รถ (เรียกเมื่อคำถามกว้างหรือไม่แน่ใจ)",
      parameters: {
        type: "object",
        properties: { date: dateProp },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "get_fuel_stock",
      description: "ยอดน้ำมันคงเหลือถังหลัก/สำรอง ณ วันที่ระบุ",
      parameters: {
        type: "object",
        properties: { date: dateProp },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "list_fuel_movements",
      description: "รายการเข้า–ออกน้ำมันในช่วงวันที่ (เติม/เบิก/โอน)",
      parameters: {
        type: "object",
        properties: {
          date_from: dateProp,
          date_to: dateProp,
          limit: {
            type: "number",
            description: "จำนวนสูงสุด (default 40, max 80)",
          },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "get_attendance",
      description: "สรุปเช็คชื่อมาทำงาน/ลางาน (คนขับรถ + ท่าทราย)",
      parameters: {
        type: "object",
        properties: { date: dateProp },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "list_leaves",
      description: "รายการลางานในช่วงวันที่",
      parameters: {
        type: "object",
        properties: {
          date_from: dateProp,
          date_to: dateProp,
          limit: { type: "number" },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "list_advances",
      description: "รายการเบิกเงินในช่วงวันที่",
      parameters: {
        type: "object",
        properties: {
          date_from: dateProp,
          date_to: dateProp,
          limit: { type: "number" },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "get_vehicle_usage",
      description: "สรุปการใช้รถดรัม + แม็คโครในวันนั้น",
      parameters: {
        type: "object",
        properties: { date: dateProp },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "list_vehicles",
      description: "รายชื่อรถในระบบ (catalog)",
      parameters: { type: "object", properties: {} },
    },
  },
  {
    type: "function",
    function: {
      name: "list_maintenance",
      description: "รายการบำรุงรักษา/แจ้งซ่อมในช่วงวันที่",
      parameters: {
        type: "object",
        properties: {
          date_from: dateProp,
          date_to: dateProp,
          limit: { type: "number" },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "list_work_plans",
      description: "แผนงานจากโมดูลวางแผนงานในช่วงวันที่",
      parameters: {
        type: "object",
        properties: {
          date_from: dateProp,
          date_to: dateProp,
          limit: { type: "number" },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "get_sand_daily",
      description: "บันทึกงานท่าทราย (DailyLog Sand) ในวันนั้น",
      parameters: {
        type: "object",
        properties: { date: dateProp },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "search_employees",
      description: "ค้นหาพนักงานด้วยชื่อ/ชื่อเล่น (หรือ list พนักงานที่ยัง active)",
      parameters: {
        type: "object",
        properties: {
          query: {
            type: "string",
            description: "ชื่อหรือชื่อเล่น ว่าง = รายชื่อ active สูงสุด 60 คน",
          },
        },
      },
    },
  },
];

function ymdOrToday(raw: unknown, fallback = bangkokYmd()): string {
  const s = String(raw ?? "").trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s;
  return fallback;
}

function daysAgoYmd(n: number, from = bangkokYmd()): string {
  const [y, m, d] = from.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() - n);
  return dt.toISOString().slice(0, 10);
}

function clampLimit(raw: unknown, def = 40, max = 80): number {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return def;
  return Math.min(Math.floor(n), max);
}

function empDisplay(e: {
  id: string;
  name?: string | null;
  nickname?: string | null;
}): string {
  const nick = (e.nickname ?? "").trim();
  if (nick) return nick;
  return (e.name ?? "").trim() || e.id;
}

async function nameMap(
  admin: SupabaseClient,
  ids: string[],
): Promise<Record<string, string>> {
  const uniq = [...new Set(ids.filter(Boolean))];
  const out: Record<string, string> = {};
  if (uniq.length === 0) return out;
  const { data } = await admin
    .from("employees")
    .select("id,name,nickname")
    .in("id", uniq);
  for (const e of data ?? []) out[e.id] = empDisplay(e);
  return out;
}

function money(n: unknown): string {
  const v = Number(n);
  if (!Number.isFinite(v)) return "—";
  return v.toLocaleString("th-TH");
}

async function listFuelMovements(
  admin: SupabaseClient,
  dateFrom: string,
  dateTo: string,
  limit: number,
): Promise<string> {
  const { data, error } = await admin
    .from("transactions")
    .select(
      "date,sub_category,quantity,unit,fuel_type,fuel_tank,fuel_movement,vehicle_name,description,created_at",
    )
    .eq("category", "Fuel")
    .gte("date", dateFrom)
    .lte("date", dateTo)
    .order("date", { ascending: false })
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw new Error(error.message);
  const rows = data ?? [];
  if (rows.length === 0) {
    return `รายการน้ำมัน ${dateFrom}–${dateTo}\nยังไม่มีรายการ`;
  }
  const lines = [
    `รายการน้ำมัน ${dateFrom}–${dateTo} (${rows.length} รายการล่าสุด)`,
    "",
  ];
  for (const r of rows) {
    const qty = Number(r.quantity);
    const q = Number.isFinite(qty) ? `${qty} ${r.unit || "L"}` : "—";
    lines.push(
      `${r.date} · ${r.fuel_movement || r.sub_category || "—"} · ${r.fuel_type || "—"} · ถัง ${r.fuel_tank || "—"} · ${q}` +
        (r.vehicle_name ? ` · ${r.vehicle_name}` : ""),
    );
  }
  return lines.join("\n");
}

async function listLeaves(
  admin: SupabaseClient,
  dateFrom: string,
  dateTo: string,
  limit: number,
): Promise<string> {
  const { data, error } = await admin
    .from("transactions")
    .select(
      "date,category,type,sub_category,labor_status,employee_ids,leave_reason,leave_days,description,work_details",
    )
    .gte("date", dateFrom)
    .lte("date", dateTo)
    .or("category.eq.Leave,type.eq.Leave,labor_status.in.(Leave,Sick,Personal)")
    .order("date", { ascending: false })
    .limit(limit);
  if (error) throw new Error(error.message);
  const rows = (data ?? []).filter((r) => {
    const cat = String(r.category ?? "");
    const typ = String(r.type ?? "").toLowerCase();
    const ls = String(r.labor_status ?? "").toLowerCase();
    return (
      cat === "Leave" ||
      typ === "leave" ||
      ls === "leave" ||
      ls === "sick" ||
      ls === "personal"
    );
  });
  if (rows.length === 0) {
    return `ลางาน ${dateFrom}–${dateTo}\nยังไม่มีรายการ`;
  }
  const ids = rows.flatMap((r) =>
    Array.isArray(r.employee_ids)
      ? r.employee_ids.map((x: unknown) => String(x ?? "").trim())
      : []
  );
  const names = await nameMap(admin, ids);
  const lines = [`ลางาน ${dateFrom}–${dateTo} (${rows.length} รายการ)`, ""];
  for (const r of rows) {
    const eids = Array.isArray(r.employee_ids)
      ? r.employee_ids.map((x: unknown) => String(x ?? "").trim()).filter(Boolean)
      : [];
    const who = eids.map((id) => names[id] || id).join(", ") || "—";
    const reason = (r.leave_reason || r.sub_category || r.labor_status || "")
      .toString()
      .trim() || "—";
    const days = r.leave_days != null ? ` · ${r.leave_days} วัน` : "";
    lines.push(`${r.date} · ${who} · ${reason}${days}`);
  }
  return lines.join("\n");
}

async function listAdvances(
  admin: SupabaseClient,
  dateFrom: string,
  dateTo: string,
  limit: number,
): Promise<string> {
  const { data, error } = await admin
    .from("transactions")
    .select(
      "date,employee_ids,advance_amount,amount,work_details,description,sub_category,labor_status",
    )
    .eq("category", "Labor")
    .gte("date", dateFrom)
    .lte("date", dateTo)
    .or("sub_category.eq.Advance,labor_status.eq.Advance")
    .order("date", { ascending: false })
    .limit(limit);
  if (error) throw new Error(error.message);
  const rows = data ?? [];
  if (rows.length === 0) {
    return `เบิกเงิน ${dateFrom}–${dateTo}\nยังไม่มีรายการ`;
  }
  const ids = rows.flatMap((r) =>
    Array.isArray(r.employee_ids)
      ? r.employee_ids.map((x: unknown) => String(x ?? "").trim())
      : []
  );
  const names = await nameMap(admin, ids);
  const lines = [`เบิกเงิน ${dateFrom}–${dateTo} (${rows.length} รายการ)`, ""];
  let sum = 0;
  for (const r of rows) {
    const eids = Array.isArray(r.employee_ids)
      ? r.employee_ids.map((x: unknown) => String(x ?? "").trim()).filter(Boolean)
      : [];
    const who = eids.map((id) => names[id] || id).join(", ") || "—";
    const amt = Number(r.advance_amount ?? r.amount ?? 0);
    if (Number.isFinite(amt)) sum += amt;
    lines.push(`${r.date} · ${who} · ${money(amt)} บาท`);
  }
  lines.push("", `รวมประมาณ: ${money(sum)} บาท`);
  return lines.join("\n");
}

async function listMaintenance(
  admin: SupabaseClient,
  dateFrom: string,
  dateTo: string,
  limit: number,
): Promise<string> {
  const { data, error } = await admin
    .from("transactions")
    .select(
      "date,sub_category,work_type,vehicle_name,description,amount,mileage,work_details",
    )
    .eq("category", "Maintenance")
    .gte("date", dateFrom)
    .lte("date", dateTo)
    .order("date", { ascending: false })
    .limit(limit);
  if (error) throw new Error(error.message);
  const rows = data ?? [];
  if (rows.length === 0) {
    return `บำรุงรักษา ${dateFrom}–${dateTo}\nยังไม่มีรายการ`;
  }
  const lines = [
    `บำรุงรักษา ${dateFrom}–${dateTo} (${rows.length} รายการ)`,
    "",
  ];
  for (const r of rows) {
    const asset = (r.vehicle_name || r.description || "—").toString().trim();
    const kind = (r.sub_category || "—").toString().trim();
    const amt = r.amount != null ? ` · ${money(r.amount)} บาท` : "";
    lines.push(
      `${r.date} · ${kind} · ${asset}${amt}` +
        (r.work_type ? ` · กลุ่ม ${r.work_type}` : ""),
    );
  }
  return lines.join("\n");
}

async function listWorkPlans(
  admin: SupabaseClient,
  dateFrom: string,
  dateTo: string,
  limit: number,
): Promise<string> {
  const { data, error } = await admin
    .from("work_plans")
    .select("plan_date,title,note,scope,status,lane,work_type")
    .gte("plan_date", dateFrom)
    .lte("plan_date", dateTo)
    .order("plan_date", { ascending: true })
    .limit(limit);
  if (error) throw new Error(error.message);
  const rows = data ?? [];
  if (rows.length === 0) {
    return `แผนงาน ${dateFrom}–${dateTo}\nยังไม่มีแผน`;
  }
  const lines = [`แผนงาน ${dateFrom}–${dateTo} (${rows.length} รายการ)`, ""];
  for (const r of rows) {
    lines.push(
      `${r.plan_date} · [${r.status || "—"}] ${r.title || "—"}` +
        (r.lane ? ` · ${r.lane}` : "") +
        (r.scope ? ` · ${r.scope}` : ""),
    );
    const note = (r.note ?? "").toString().trim();
    if (note) lines.push(`  หมายเหตุ: ${note.slice(0, 120)}`);
  }
  return lines.join("\n");
}

async function listVehiclesCatalog(admin: SupabaseClient): Promise<string> {
  const { data, error } = await admin
    .from("vehicles")
    .select("id,name,default_driver_id,sort_order")
    .order("sort_order", { ascending: true });
  if (error) throw new Error(error.message);
  const rows = data ?? [];
  if (rows.length === 0) return "ยังไม่มีรายการรถในระบบ";
  const driverIds = rows
    .map((r) => (r.default_driver_id ?? "").trim())
    .filter(Boolean);
  const names = await nameMap(admin, driverIds);
  const lines = [`รายชื่อรถในระบบ (${rows.length})`, ""];
  for (const r of rows) {
    const d = (r.default_driver_id ?? "").trim();
    lines.push(
      `${r.name || r.id}` + (d ? ` · คนขับหลัก ${names[d] || d}` : ""),
    );
  }
  return lines.join("\n");
}

async function getSandDaily(
  admin: SupabaseClient,
  date: string,
): Promise<string> {
  const { data, error } = await admin
    .from("transactions")
    .select(
      "sand_morning,sand_afternoon,sand_machine_type,sand_operators,drums_obtained,drums_washed_at_home,sand_work_start,sand_morning_start,sand_afternoon_start,sand_evening_end,description",
    )
    .eq("date", date)
    .eq("category", "DailyLog")
    .eq("sub_category", "Sand")
    .order("created_at", { ascending: true });
  if (error) throw new Error(error.message);
  const rows = data ?? [];
  if (rows.length === 0) {
    return `งานท่าทราย ${formatDateThaiBE(date)}\nยังไม่มีบันทึก`;
  }
  const lines = [`งานท่าทราย ${formatDateThaiBE(date)} (${date})`, ""];
  for (const r of rows) {
    lines.push(
      `เช้า ${r.sand_morning ?? "—"} / บ่าย ${r.sand_afternoon ?? "—"}` +
        (r.sand_machine_type ? ` · เครื่อง ${r.sand_machine_type}` : "") +
        (r.drums_obtained != null ? ` · ดรัมได้ ${r.drums_obtained}` : ""),
    );
  }
  return lines.join("\n");
}

async function searchEmployees(
  admin: SupabaseClient,
  query: string,
): Promise<string> {
  const q = query.trim().replace(/[%(),]/g, "").slice(0, 40);
  let data: Array<{
    id: string;
    name?: string | null;
    nickname?: string | null;
    type?: string | null;
    position?: string | null;
    phone?: string | null;
  }> | null = null;
  let error: { message: string } | null = null;

  if (q) {
    const res = await admin
      .from("employees")
      .select("id,name,nickname,type,position,phone,inactive")
      .eq("inactive", false)
      .or(`name.ilike.%${q}%,nickname.ilike.%${q}%`)
      .order("name", { ascending: true })
      .limit(40);
    data = res.data;
    error = res.error;
  } else {
    const res = await admin
      .from("employees")
      .select("id,name,nickname,type,position,phone,inactive")
      .eq("inactive", false)
      .order("name", { ascending: true })
      .limit(60);
    data = res.data;
    error = res.error;
  }
  if (error) throw new Error(error.message);
  const rows = data ?? [];
  if (rows.length === 0) {
    return q ? `ไม่พบพนักงานที่ตรงกับ "${q}"` : "ยังไม่มีพนักงาน active";
  }
  const lines = [
    q ? `ค้นหาพนักงาน "${q}" (${rows.length})` : `พนักงาน active (${rows.length})`,
    "",
  ];
  for (const e of rows) {
    lines.push(
      `${empDisplay(e)}` +
        (e.position ? ` · ${e.position}` : "") +
        (e.type ? ` · ${e.type}` : "") +
        (e.phone ? ` · ${e.phone}` : ""),
    );
  }
  return lines.join("\n");
}

export async function runLineQaTool(
  admin: SupabaseClient,
  name: string,
  argsRaw: Record<string, unknown>,
): Promise<string> {
  const today = bangkokYmd();
  const date = ymdOrToday(argsRaw.date, today);
  const dateTo = ymdOrToday(argsRaw.date_to, today);
  const dateFrom = ymdOrToday(argsRaw.date_from, daysAgoYmd(7, dateTo));
  const limit = clampLimit(argsRaw.limit);

  switch (name) {
    case "get_ops_snapshot": {
      const [fuel, att, veh] = await Promise.all([
        buildFuelReportText(admin, date),
        buildAttendanceReportText(admin, date),
        buildVehicleReportText(admin, date),
      ]);
      return [fuel, "", "——", "", att, "", "——", "", veh].join("\n");
    }
    case "get_fuel_stock":
      return await buildFuelReportText(admin, date);
    case "list_fuel_movements":
      return await listFuelMovements(admin, dateFrom, dateTo, limit);
    case "get_attendance":
      return await buildAttendanceReportText(admin, date);
    case "list_leaves":
      return await listLeaves(admin, dateFrom, dateTo, limit);
    case "list_advances":
      return await listAdvances(admin, dateFrom, dateTo, limit);
    case "get_vehicle_usage":
      return await buildVehicleReportText(admin, date);
    case "list_vehicles":
      return await listVehiclesCatalog(admin);
    case "list_maintenance":
      return await listMaintenance(admin, dateFrom, dateTo, limit);
    case "list_work_plans":
      return await listWorkPlans(admin, dateFrom, dateTo, limit);
    case "get_sand_daily":
      return await getSandDaily(admin, date);
    case "search_employees":
      return await searchEmployees(admin, String(argsRaw.query ?? ""));
    default:
      return `ไม่รู้จักเครื่องมือ: ${name}`;
  }
}
