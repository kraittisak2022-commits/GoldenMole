/**
 * สร้างข้อความรายงานสำหรับตอบในแชทส่วนตัว / ใช้ร่วม cron
 * แชทส่วนตัว: ใช้ AI (OpenRouter) วิเคราะห์จากข้อมูลจริง + fallback คำสั่งเดิม
 */
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";
import {
  FUEL_STOCK_CUTOVER_YMD,
  buildDailyFuelStockLineText,
  computeFuelStockBalances,
  type FuelTx,
} from "./fuel_stock_balance.ts";
import {
  defaultLineQaModel,
  openRouterChat,
} from "./openrouter_chat.ts";

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

export function bangkokYmd(d = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Bangkok",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}

export function formatDateThaiBE(ymd: string): string {
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

function empDisplay(
  e: { id: string; name?: string | null; nickname?: string | null },
): string {
  const nick = (e.nickname ?? "").trim();
  if (nick) return nick;
  const name = (e.name ?? "").trim();
  return name || e.id;
}

function stripRecorder(desc: string): string {
  return desc.replace(/\s*\(ผู้กรอก:[^)]+\)\s*$/u, "").trim();
}

export function qaHelpText(): string {
  return [
    "━━━━ GoldenMole ━━━━",
    "ถามด้วยภาษาธรรมชาติได้ (AI สรุปจากข้อมูลจริง)",
    "",
    "ตัวอย่าง:",
    "• วันนี้มีใครลาบ้าง",
    "• น้ำมันเหลือเท่าไหร่ ควรเติมไหม",
    "• สรุปการใช้รถดรัมกับแม็คโคร",
    "",
    "คำลัด: น้ำมัน / เช็คชื่อ / รถ / สรุป",
    "รายงานอัตโนมัติ 09:00 ส่งเข้ากลุ่มเท่านั้น",
  ].join("\n");
}

async function resolveOpenRouterApiKey(
  admin: SupabaseClient,
): Promise<string> {
  const fromEnv = (Deno.env.get("OPENROUTER_API_KEY") ?? "").trim();
  if (fromEnv) return fromEnv;
  const { data } = await admin
    .from("app_settings")
    .select("app_defaults")
    .eq("id", "default")
    .maybeSingle();
  const defaults = (data?.app_defaults ?? {}) as Record<string, unknown>;
  return String(defaults.openRouterApiKey ?? "").trim();
}

export async function buildOpsContextPack(
  admin: SupabaseClient,
  dateYmd: string,
): Promise<string> {
  const [fuel, att, veh] = await Promise.all([
    buildFuelReportText(admin, dateYmd),
    buildAttendanceReportText(admin, dateYmd),
    buildVehicleReportText(admin, dateYmd),
  ]);
  return [
    `วันที่อ้างอิง (Asia/Bangkok): ${dateYmd} = ${formatDateThaiBE(dateYmd)}`,
    "",
    "=== น้ำมันคงเหลือ ===",
    fuel,
    "",
    "=== เช็คชื่อ ===",
    att,
    "",
    "=== การใช้รถ ===",
    veh,
  ].join("\n");
}

const QA_SYSTEM = [
  "คุณเป็นผู้ช่วยวิเคราะห์ข้อมูลปฏิบัติการของบริษัทก่อสร้าง GoldenMole",
  "ตอบเป็นภาษาไทย สั้น ชัด อ่านง่ายบน LINE (ใช้ขึ้นบรรทัดใหม่ ไม่ใช้ markdown หนัก)",
  "ใช้เฉพาะข้อมูลในบริบทที่ให้มาเท่านั้น ห้ามแต่งตัวเลขหรือชื่อที่ไม่มีในข้อมูล",
  "ถ้าข้อมูลไม่พอ ให้บอกตรงๆ ว่ายังไม่มีในระบบ และแนะนำว่าควรถามเรื่องใด",
  "สรุปประเด็นสำคัญก่อน แล้วค่อยรายละเอียดสั้นๆ ถ้าผู้ใช้ขอวิเคราะห์/แนวโน้ม ให้วิเคราะห์จากตัวเลขที่มีอย่างระมัดระวัง",
  "ความยาวรวมไม่เกินประมาณ 3500 ตัวอักษร",
].join(". ");

export async function answerLineQaWithAi(
  admin: SupabaseClient,
  userText: string,
  dateYmd = bangkokYmd(),
): Promise<{ text: string; usedAi: boolean; error?: string }> {
  const apiKey = await resolveOpenRouterApiKey(admin);
  if (!apiKey) {
    return {
      text: await answerLineQaKeyword(admin, userText, dateYmd),
      usedAi: false,
      error: "missing_openrouter_key",
    };
  }

  try {
    const context = await buildOpsContextPack(admin, dateYmd);
    const { text, model } = await openRouterChat({
      apiKey,
      model: defaultLineQaModel(),
      messages: [
        { role: "system", content: QA_SYSTEM },
        {
          role: "user",
          content: [
            "ข้อมูลจากระบบ (อ้างอิงได้เท่านั้น):",
            context,
            "",
            `คำถามจากผู้ใช้: ${userText.trim()}`,
          ].join("\n"),
        },
      ],
      temperature: 0.2,
      maxTokens: 1200,
      timeoutMs: 55_000,
    });
    console.log(`LINE QA AI ok model=${model}`);
    return { text, usedAi: true };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("LINE QA AI failed", msg);
    const fallback = await answerLineQaKeyword(admin, userText, dateYmd);
    return {
      text: `${fallback}\n\n(หมายเหตุ: AI วิเคราะห์ไม่สำเร็จ — แสดงข้อมูลดิบแทน)`,
      usedAi: false,
      error: msg.slice(0, 200),
    };
  }
}

export async function buildFuelReportText(
  admin: SupabaseClient,
  dateYmd: string,
): Promise<string> {
  const { data: settingsRow } = await admin
    .from("app_settings")
    .select("fuel_opening_stock")
    .eq("id", "default")
    .maybeSingle();
  const openingRaw = settingsRow?.fuel_opening_stock;
  const opening =
    openingRaw && typeof openingRaw === "object"
      ? (openingRaw as Record<string, unknown>)
      : {};
  const num = (v: unknown) => {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  };

  const txs: FuelTx[] = [];
  const pageSize = 1000;
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
    if (error) throw new Error(error.message);
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
  return buildDailyFuelStockLineText(dateYmd, bal, formatDateThaiBE);
}

export async function buildVehicleReportText(
  admin: SupabaseClient,
  dateYmd: string,
): Promise<string> {
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
        "vehicle_id,vehicle_name,driver_id,work_details,created_at",
      )
      .eq("date", dateYmd)
      .eq("category", "Vehicle")
      .order("created_at", { ascending: true }),
  ]);
  if (tripsRes.error) throw new Error(tripsRes.error.message);
  if (vehRes.error) throw new Error(vehRes.error.message);

  const trips = tripsRes.data ?? [];
  const macros = (vehRes.data ?? []).filter((t) =>
    isMacroVehicleName(vehicleLabel(t))
  );
  if (trips.length === 0 && macros.length === 0) {
    return `การใช้รถ ${formatDateThaiBE(dateYmd)}\n\nยังไม่มีบันทึกรถดรัมหรือแม็คโครวันนี้`;
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
    for (const e of emps ?? []) nameById[e.id] = empDisplay(e);
  }

  const lines = [
    `การใช้รถ ${formatDateThaiBE(dateYmd)}`,
    "",
    `บันทึกรถดรัม จำนวน ${trips.length} คัน`,
  ];
  trips.forEach((t, i) => {
    const d = nameById[(t.driver_id ?? "").trim()] ||
      (t.driver_id ?? "").trim() ||
      "—";
    lines.push(`คันที่ ${i + 1} : ${vehicleLabel(t)} · ${d}`);
  });
  lines.push("", `รถแม็คโคร จำนวน ${macros.length} คัน`);
  macros.forEach((t, i) => {
    const d = nameById[(t.driver_id ?? "").trim()] ||
      (t.driver_id ?? "").trim() ||
      "—";
    const work = ((t.work_details ?? "").trim() || "—");
    lines.push(`คันที่ ${i + 1} : ${vehicleLabel(t)} · ${d} · ${work}`);
  });
  return lines.join("\n").trim();
}

export async function buildAttendanceReportText(
  admin: SupabaseClient,
  dateYmd: string,
): Promise<string> {
  const { data: rows, error } = await admin
    .from("transactions")
    .select(
      "category,type,sub_category,labor_status,employee_ids,description,leave_reason",
    )
    .eq("date", dateYmd)
    .or("category.eq.Labor,category.eq.Leave,type.eq.Leave");
  if (error) throw new Error(error.message);

  const sandPresent: string[] = [];
  const sandLeave: string[] = [];
  const drvPresent: string[] = [];
  const drvLeave: string[] = [];

  const isSand = (desc: string, reason: string) =>
    (desc + " " + reason).includes("ท่าทราย");
  const isDrv = (desc: string, reason: string) =>
    (desc + " " + reason).includes("คนขับรถ");

  for (const t of rows ?? []) {
    const desc = stripRecorder(String(t.description ?? ""));
    const reason = String(t.leave_reason ?? "").trim();
    const ids = Array.isArray(t.employee_ids)
      ? t.employee_ids.map((x: unknown) => String(x ?? "").trim()).filter(Boolean)
      : [];
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
      if (isDrv(desc, reason)) drvPresent.push(...ids);
      else if (isSand(desc, reason)) sandPresent.push(...ids);
      else if (desc.includes("เช็คชื่อ")) sandPresent.push(...ids);
      continue;
    }
    if (isLeave && (desc.includes("เช็คชื่อ") || reason.includes("เช็คชื่อ"))) {
      if (isDrv(desc, reason)) drvLeave.push(...ids);
      else sandLeave.push(...ids);
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
    return `━━━━ GoldenMole ━━━━\nวันที่ : ${formatDateThaiBE(dateYmd)} (${dateYmd})\nเช็คชื่อ\nยังไม่มีข้อมูลวันนี้`;
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
    for (const e of emps ?? []) nameById[e.id] = empDisplay(e);
  }
  const join = (ids: string[]) =>
    ids.length === 0 ? "—" : ids.map((id) => nameById[id] || id).join(", ");

  return [
    "━━━━ GoldenMole ━━━━",
    `วันที่ : ${formatDateThaiBE(dateYmd)} (${dateYmd})`,
    `เช็คชื่อ · ${title}`,
    `มาทำงาน :${present.length} คน`,
    "",
    "รายชื่อมาทำงาน :",
    join(present),
    "",
    `ลางาน : ${leave.length} คน`,
    `รายชื่อลางาน : ${join(leave)}`,
  ].join("\n");
}

/** คำสั่งลัด / fallback เมื่อไม่มี AI */
export async function answerLineQaKeyword(
  admin: SupabaseClient,
  userText: string,
  dateYmd = bangkokYmd(),
): Promise<string> {
  const q = userText.trim().toLowerCase();
  if (!q || q === "?" || q === "？") return qaHelpText();
  if (
    q.includes("ช่วย") ||
    q.includes("เมนู") ||
    q.includes("help") ||
    q.includes("คำสั่ง")
  ) {
    return qaHelpText();
  }

  const wantFuel = q.includes("น้ำมัน") || q.includes("ถัง");
  const wantAtt =
    q.includes("เช็คชื่อ") ||
    q.includes("เชคชื่อ") ||
    q.includes("มาทำงาน") ||
    q.includes("ลางาน");
  const wantVeh =
    q.includes("รถ") ||
    q.includes("ดรัม") ||
    q.includes("ดั๊ม") ||
    q.includes("แม็คโคร") ||
    q.includes("แมคโคร") ||
    q.includes("เที่ยว");
  const wantAll = q.includes("สรุป") || q.includes("วันนี้");

  try {
    if (wantAll) {
      const [fuel, att, veh] = await Promise.all([
        buildFuelReportText(admin, dateYmd),
        buildAttendanceReportText(admin, dateYmd),
        buildVehicleReportText(admin, dateYmd),
      ]);
      return [fuel, "", "——", "", att, "", "——", "", veh].join("\n");
    }
    if (wantFuel && !wantAtt && !wantVeh) {
      return await buildFuelReportText(admin, dateYmd);
    }
    if (wantAtt && !wantFuel && !wantVeh) {
      return await buildAttendanceReportText(admin, dateYmd);
    }
    if (wantVeh && !wantFuel && !wantAtt) {
      return await buildVehicleReportText(admin, dateYmd);
    }
    if (wantFuel || wantAtt || wantVeh) {
      const parts: string[] = [];
      if (wantFuel) parts.push(await buildFuelReportText(admin, dateYmd));
      if (wantAtt) parts.push(await buildAttendanceReportText(admin, dateYmd));
      if (wantVeh) parts.push(await buildVehicleReportText(admin, dateYmd));
      return parts.join("\n\n——\n\n");
    }
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return `ดึงข้อมูลไม่สำเร็จ: ${msg}`;
  }

  return ["ยังไม่เข้าใจคำถาม", "", qaHelpText()].join("\n");
}

/** ทางหลัก: AI วิเคราะห์ (ยกเว้นเมนูช่วยเหลือ) */
export async function answerLineQa(
  admin: SupabaseClient,
  userText: string,
  dateYmd = bangkokYmd(),
): Promise<string> {
  const q = userText.trim().toLowerCase();
  if (
    !q ||
    q === "?" ||
    q === "？" ||
    q.includes("ช่วย") ||
    q.includes("เมนู") ||
    q.includes("help") ||
    q.includes("คำสั่ง")
  ) {
    return qaHelpText();
  }
  const result = await answerLineQaWithAi(admin, userText, dateYmd);
  return result.text;
}
