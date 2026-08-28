import type { Transaction } from '../types';

const TZ_TH = 'Asia/Bangkok';

/** แปลงปริมาณน้ำมันในธุรกรรมเป็นหน่วยลิตร (รองรับ L / gallon / แกลลอน) */
export function fuelTxToLiters(t: Transaction): number {
    const q = Number(t.quantity) || 0;
    if (!q) return 0;
    const u = (t.unit || 'L').toLowerCase();
    if (u === 'gallon' || u === 'แกลลอน') return q * 3.785411784;
    return q;
}

/** รับเข้าสต็อก vs เติมรถ — ข้อมูลเก่า: มี vehicleId = เติมรถ, ไม่มี = รับเข้า */
export function inferFuelMovement(t: Transaction): 'stock_in' | 'stock_out' {
    if (t.category !== 'Fuel') return 'stock_out';
    if (t.fuelMovement === 'stock_in' || t.fuelMovement === 'stock_out') return t.fuelMovement;
    return t.vehicleId ? 'stock_out' : 'stock_in';
}

/** `subCategory` ของแถวเบิกน้ำมันออกจากถัง (แอปมือถือ เมนู «เบิกน้ำมัน») */
export const FUEL_WITHDRAW_SUB_CATEGORY = 'Withdraw';
export const FUEL_TRANSFER_SUB_CATEGORY = 'Transfer';
export const FUEL_SAND_SIEVE_SUB_CATEGORY = 'SandSieve';
/** ชื่อรถ/เครื่องจักรเมื่อเครื่องร่อนทรายทำงาน */
export const FUEL_SAND_SIEVE_VEHICLE_ID = 'เครื่องจักรร่อนทราย เครื่องปั่นไฟ';
/** เพิ่มน้ำมันเข้าถังหลัก (ซื้อ/เติมสต็อก) — ไม่รวมโอนเข้าถังสำรอง */
export const FUEL_STOCK_IN_SUB_CATEGORY = 'StockIn';
/** ใช้น้ำมันรถ/แม็คโคร (เมนูการใช้น้ำมัน) */
export const FUEL_VEHICLE_USAGE_SUB_CATEGORY = 'VehicleUsage';
export const FUEL_TANK_MAIN = 'main';
export const FUEL_TANK_RESERVE = 'reserve';
export const FUEL_TANK_CAPACITY_MAIN = 12000;
export const FUEL_TANK_CAPACITY_RESERVE = 1000;

/**
 * วันตัดยอดสต็อกน้ำมัน — ก่อนวันนี้ถือว่าเหลือ 0 (ถูกใช้หมดแล้ว)
 * ตั้งแต่วันนี้หักลบจากถังปกติ · พ.ศ. 1 ส.ค. 2569 = ค.ศ. 2026-08-01
 */
export const FUEL_STOCK_CUTOVER_YMD = '2026-08-01';

type FuelDayBucket = { stockIn: number; withdraw: number };

export function normalizeFuelTank(raw?: string | null): 'main' | 'reserve' {
    const v = String(raw ?? '').trim().toLowerCase();
    if (v === FUEL_TANK_RESERVE || v === 'สำรอง') return 'reserve';
    return 'main';
}

/**
 * ถังที่ใช้คิดยอด — ตรงกับมือถือ `fuelUsageTankOf`
 * แถว VehicleUsage ที่ไม่ระบุถัง = ถังสำรอง; ประเภทอื่นว่าง = ถังหลัก
 */
export function fuelUsageTankOf(t: Transaction): 'main' | 'reserve' {
    const raw = String(t.fuelTank ?? '').trim();
    if (raw) return normalizeFuelTank(raw);
    const sub = String(t.subCategory ?? '').trim();
    if (t.category === 'Fuel' && sub === FUEL_VEHICLE_USAGE_SUB_CATEGORY) {
        return FUEL_TANK_RESERVE;
    }
    return FUEL_TANK_MAIN;
}

export type FuelStockBalances = {
    /** ดีเซลถังหลัก (ความเข้ากันได้เดิม) */
    Diesel: number;
    /** เบนซินถังหลัก */
    Benzine: number;
    DieselReserve: number;
    BenzineReserve: number;
    /** ลิตรที่ถังสำรองติดลบ (0 ถ้าไม่ติดลบ) — ใช้เตือนว่าขาดบันทึกโอน */
    reserveShortfallLiters: number;
};

export type ComputeFuelStockBalancesOptions = {
    Diesel?: number;
    Benzine?: number;
    DieselReserve?: number;
    BenzineReserve?: number;
    /** ลิตรร่อนทรายประมาณรายวัน (เฉพาะวันที่ยังไม่มีแถว SandSieve) — หักจากถังสำรอง */
    estimatedSieveByDay?: Record<string, number>;
};

/**
 * คงเหลือแยกถังหลัก/ถังสำรอง — สูตรเดียวกับมือถือ
 *
 * แต่ละแถวหัก/เติมถังของตัวเอง — ไม่หักล้างข้ามแถว
 * `delta = stockIn − withdraw`
 *
 * - รับเข้า (StockIn) → ถังหลัก
 * - โอนหลัก→สำรอง (Transfer / เบิกเครื่องจักรแบบเก่า) → หักหลัก บวกสำรอง (ยังไม่ใช้)
 * - ใช้แล้ว (VehicleUsage, เบิกปั่นไฟ/อื่น/รถยนต์, SandSieve) → หักตามถังที่ติดป้าย
 * - รายการก่อน [FUEL_STOCK_CUTOVER_YMD] ไม่ถูกนับ
 */
export function computeFuelStockBalances(
    transactions: Transaction[],
    opening?: ComputeFuelStockBalancesOptions
): FuelStockBalances {
    const buckets = new Map<string, FuelDayBucket>();
    const bucketFor = (date: string, tank: 'main' | 'reserve', ft: 'Diesel' | 'Benzine') => {
        const key = `${date}|${tank}|${ft}`;
        let bucket = buckets.get(key);
        if (!bucket) {
            bucket = { stockIn: 0, withdraw: 0 };
            buckets.set(key, bucket);
        }
        return bucket;
    };

    const transferMachineDays = new Set<string>();
    for (const t of transactions) {
        if (t.category !== 'Fuel' || t.type !== 'Expense') continue;
        const day = normalizeDate(t.date);
        if (day < FUEL_STOCK_CUTOVER_YMD) continue;
        if (
            t.subCategory === FUEL_TRANSFER_SUB_CATEGORY
            && String(t.workType ?? '').trim().toLowerCase() === 'machine'
        ) {
            transferMachineDays.add(day);
        }
    }

    for (const t of transactions) {
        if (t.category !== 'Fuel' || t.type !== 'Expense') continue;
        const day = normalizeDate(t.date);
        if (day < FUEL_STOCK_CUTOVER_YMD) continue;
        const liters = fuelTxToLiters(t);
        if (!liters) continue;
        const ft = t.fuelType === 'Benzine' ? 'Benzine' : 'Diesel';
        const tank = fuelUsageTankOf(t);
        const bucket = bucketFor(day, tank, ft);
        const sub = String(t.subCategory ?? '').trim();
        const purpose = String(t.workType ?? '').trim().toLowerCase();
        const movement = inferFuelMovement(t);

        if (movement === 'stock_in') {
            bucket.stockIn += liters;
            continue;
        }
        if (sub === FUEL_WITHDRAW_SUB_CATEGORY) {
            bucket.withdraw += liters;
            // แอปเก่า: เบิกเติมเครื่องจักรแถวเดียว — ตีความเป็นโอนหลัก→สำรอง
            if (purpose === 'machine' && !transferMachineDays.has(day)) {
                bucketFor(day, FUEL_TANK_RESERVE, ft).stockIn += liters;
            }
            continue;
        }
        if (
            sub === FUEL_TRANSFER_SUB_CATEGORY
            || sub === FUEL_SAND_SIEVE_SUB_CATEGORY
            || sub === FUEL_VEHICLE_USAGE_SUB_CATEGORY
        ) {
            // VehicleUsage หักเฉพาะถังที่ติดป้าย — ไม่นับ stock_out ทั่วไปที่มีรถ
            bucket.withdraw += liters;
        }
    }

    const estimated = opening?.estimatedSieveByDay;
    if (estimated) {
        for (const [day, liters] of Object.entries(estimated)) {
            if (!liters || day < FUEL_STOCK_CUTOVER_YMD) continue;
            bucketFor(normalizeDate(day), FUEL_TANK_RESERVE, 'Diesel').withdraw += liters;
        }
    }

    let mainD = opening?.Diesel ?? 0;
    let mainB = opening?.Benzine ?? 0;
    let reserveD = opening?.DieselReserve ?? 0;
    let reserveB = opening?.BenzineReserve ?? 0;
    for (const [key, bucket] of buckets) {
        const delta = bucket.stockIn - bucket.withdraw;
        const isReserve = key.includes('|reserve|');
        const isBenzine = key.endsWith('|Benzine');
        if (isReserve) {
            if (isBenzine) reserveB += delta;
            else reserveD += delta;
        } else if (isBenzine) {
            mainB += delta;
        } else {
            mainD += delta;
        }
    }
    const reserveShortfallLiters =
        Math.max(0, -reserveD) + Math.max(0, -reserveB);
    return {
        Diesel: mainD,
        Benzine: mainB,
        DieselReserve: reserveD,
        BenzineReserve: reserveB,
        reserveShortfallLiters,
    };
}

/** วันที่ปัจจุบันในประเทศไทย (YYYY-MM-DD) */
export const getToday = () => new Date().toLocaleDateString('en-CA', { timeZone: TZ_TH });

/** ทำให้วันที่เป็นรูปแบบ YYYY-MM-DD เสมอ (รองรับทั้ง ISO string จาก DB) */
export const normalizeDate = (d: string | undefined): string => (d && d.length >= 10 ? d.slice(0, 10) : d || '');

export const getFirstDayOfMonth = () => {
    const d = new Date();
    return new Date(d.getFullYear(), d.getMonth(), 1).toLocaleDateString('en-CA', { timeZone: TZ_TH });
};

export const getLastDayOfMonth = () => {
    const d = new Date();
    return new Date(d.getFullYear(), d.getMonth() + 1, 0).toLocaleDateString('en-CA', { timeZone: TZ_TH });
};

/** เวลาปัจจุบันในประเทศไทย รูปแบบ 24 ชม. (HH:mm) */
export const getCurrentTimeTH = () => new Date().toLocaleTimeString('th-TH', { timeZone: TZ_TH, hour: '2-digit', minute: '2-digit', hour12: false });

/** วันที่+เวลา สำหรับประเทศไทย รูปแบบ 24 ชม. */
export const formatDateTimeTH = (date?: Date | string) => {
    const d = date ? new Date(date) : new Date();
    return d.toLocaleString('th-TH', { timeZone: TZ_TH, hour12: false });
};

export const formatDateBE = (dateString?: string) => {
    if (!dateString) return '-';
    const [year, month, day] = dateString.split('-');
    if (!year || !month || !day) return dateString;
    const beYear = parseInt(year) + 543;
    return `${day}/${month}/${beYear}`;
};

/** ชื่อเดือนไทย (index 0 = มกราคม) */
export const THAI_MONTHS = [
    'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
    'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
] as const;

/** วันที่ไทยแบบชื่อเดือน เช่น 24 สิงหาคม 2569 */
export const formatDateBELong = (dateString?: string) => {
    if (!dateString) return '-';
    const [year, month, day] = dateString.split('-');
    if (!year || !month || !day) return dateString;
    const m = parseInt(month, 10);
    if (m < 1 || m > 12) return dateString;
    const beYear = parseInt(year, 10) + 543;
    return `${parseInt(day, 10)} ${THAI_MONTHS[m - 1]} ${beYear}`;
};

/** จำนวนวันในเดือน (month 1–12, year ค.ศ.) */
export const daysInMonth = (year: number, month: number) => new Date(year, month, 0).getDate();

/** รวมวัน/เดือน/ปี ค.ศ. เป็น YYYY-MM-DD (ตัดวันเกินตามเดือน) */
export const ymdFromParts = (year: number, month: number, day: number) => {
    const maxDay = daysInMonth(year, month);
    const d = Math.min(Math.max(1, day), maxDay);
    return `${year}-${String(month).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
};

export const FormatNumber = ({ value }: { value: number }) => {
    // Note: This was a component in the original code, but as a util efficiently it should return string, 
    // but for the UI consistency I will keep it as a component-like helper or just use string formatting here and Text Component in UI.
    // However, the original code used it as a Component with a tooltip. I will move the Component to `components/ui/FormatNumber.tsx` but keep logic here? 
    // No, simpler to just keep utilities as pure JS functions.
    return value.toLocaleString();
};

/** มาตรฐานการแสดงผลตัวเลขเดียวกันทั้งระบบ */
export const formatDisplayNumber = (value: number, maximumFractionDigits = 2) =>
    new Intl.NumberFormat('th-TH', {
        minimumFractionDigits: 0,
        maximumFractionDigits,
    }).format(Number.isFinite(value) ? value : 0);

export const formatDisplayCurrency = (value: number, prefix = '฿') =>
    `${prefix}${formatDisplayNumber(value)}`;

export const formatNumberShort = (value: number) => {
    let short = value.toLocaleString();
    if (value >= 1000000) short = (value / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
    else if (value >= 100000) short = (value / 1000).toFixed(0) + 'K';
    return short;
}

/**
 * วันหยุดนักขัตฤกษ์ไทย (ชุดหลักแบบคงที่)
 * หมายเหตุ: ยังไม่รวมวันเลื่อนชดเชย/วันเฉพาะปีที่ประกาศภายหลัง
 */
export const getThaiPublicHolidays = (year: number) => {
    const rows = [
        { md: '01-01', name: 'วันขึ้นปีใหม่' },
        { md: '02-12', name: 'วันมาฆบูชา' },
        { md: '04-06', name: 'วันจักรี' },
        { md: '04-13', name: 'วันสงกรานต์' },
        { md: '04-14', name: 'วันสงกรานต์' },
        { md: '04-15', name: 'วันสงกรานต์' },
        { md: '05-01', name: 'วันแรงงานแห่งชาติ' },
        { md: '05-04', name: 'วันฉัตรมงคล' },
        { md: '05-11', name: 'วันพืชมงคล (ประมาณการ)' },
        { md: '06-03', name: 'วันเฉลิมพระชนมพรรษา สมเด็จพระราชินี' },
        { md: '07-10', name: 'วันอาสาฬหบูชา (ประมาณการ)' },
        { md: '07-11', name: 'วันเข้าพรรษา (ประมาณการ)' },
        { md: '07-28', name: 'วันเฉลิมพระชนมพรรษา ร.10' },
        { md: '08-12', name: 'วันแม่แห่งชาติ' },
        { md: '10-13', name: 'วันนวมินทรมหาราช' },
        { md: '10-23', name: 'วันปิยมหาราช' },
        { md: '12-05', name: 'วันพ่อแห่งชาติ' },
        { md: '12-10', name: 'วันรัฐธรรมนูญ' },
        { md: '12-31', name: 'วันสิ้นปี' },
    ];
    return rows.map((r) => ({
        id: `holiday_${year}_${r.md}`,
        date: `${year}-${r.md}`,
        name: r.name,
    }));
};

export const getThaiPublicHolidayMap = (year: number) => {
    return Object.fromEntries(getThaiPublicHolidays(year).map((h) => [h.date, h]));
};
