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
export const FUEL_TANK_MAIN = 'main';
export const FUEL_TANK_RESERVE = 'reserve';
export const FUEL_TANK_CAPACITY_MAIN = 12000;
export const FUEL_TANK_CAPACITY_RESERVE = 1000;

/**
 * วันตัดยอดสต็อกน้ำมัน — ก่อนวันนี้ถือว่าเหลือ 0 (ถูกใช้หมดแล้ว)
 * ตั้งแต่วันนี้หักลบจากถังปกติ · พ.ศ. 1 ส.ค. 2569 = ค.ศ. 2026-08-01
 */
export const FUEL_STOCK_CUTOVER_YMD = '2026-08-01';

type FuelDayBucket = { stockIn: number; withdraw: number; machineWithdraw: number; vehicleUsage: number };

export function normalizeFuelTank(raw?: string | null): 'main' | 'reserve' {
    const v = String(raw ?? '').trim().toLowerCase();
    if (v === FUEL_TANK_RESERVE || v === 'สำรอง') return 'reserve';
    return 'main';
}

export type FuelStockBalances = {
    /** ดีเซลถังหลัก (ความเข้ากันได้เดิม) */
    Diesel: number;
    /** เบนซินถังหลัก */
    Benzine: number;
    DieselReserve: number;
    BenzineReserve: number;
};

/**
 * คงเหลือแยกถังหลัก/สำรอง
 *
 * ต่อวันต่อถังต่อชนิดน้ำมัน:
 * `delta = stockIn − withdraw − max(0, vehicleUsage − machineWithdraw)`
 *
 * รายการก่อน [FUEL_STOCK_CUTOVER_YMD] ไม่ถูกนับ — ยอดก่อนหน้า = 0
 * แถวไม่มี fuelTank → ถือเป็นถังหลัก
 */
export function computeFuelStockBalances(
    transactions: Transaction[],
    opening?: { Diesel?: number; Benzine?: number; DieselReserve?: number; BenzineReserve?: number }
): FuelStockBalances {
    const buckets = new Map<string, FuelDayBucket>();
    const bucketFor = (date: string, tank: 'main' | 'reserve', ft: 'Diesel' | 'Benzine') => {
        const key = `${date}|${tank}|${ft}`;
        let bucket = buckets.get(key);
        if (!bucket) {
            bucket = { stockIn: 0, withdraw: 0, machineWithdraw: 0, vehicleUsage: 0 };
            buckets.set(key, bucket);
        }
        return bucket;
    };

    for (const t of transactions) {
        if (t.category !== 'Fuel' || t.type !== 'Expense') continue;
        const day = normalizeDate(t.date);
        if (day < FUEL_STOCK_CUTOVER_YMD) continue;
        const liters = fuelTxToLiters(t);
        if (!liters) continue;
        const ft = t.fuelType === 'Benzine' ? 'Benzine' : 'Diesel';
        const tank = normalizeFuelTank(t.fuelTank);
        const bucket = bucketFor(day, tank, ft);
        if (inferFuelMovement(t) === 'stock_in') {
            bucket.stockIn += liters;
            continue;
        }
        if (t.subCategory === FUEL_WITHDRAW_SUB_CATEGORY) {
            bucket.withdraw += liters;
            if (String(t.workType ?? '').trim().toLowerCase() === 'machine') bucket.machineWithdraw += liters;
            continue;
        }
        if (t.subCategory === FUEL_TRANSFER_SUB_CATEGORY || t.subCategory === FUEL_SAND_SIEVE_SUB_CATEGORY) {
            bucket.withdraw += liters;
            // เติมเครื่องจักรผ่านโอนหลัก→สำรอง: นับโควตา machine บนถังนั้น
            if (
                t.subCategory === FUEL_TRANSFER_SUB_CATEGORY &&
                String(t.workType ?? '').trim().toLowerCase() === 'machine'
            ) {
                bucket.machineWithdraw += liters;
            }
            continue;
        }
        if (t.vehicleId) bucket.vehicleUsage += liters;
    }

    let mainD = opening?.Diesel ?? 0;
    let mainB = opening?.Benzine ?? 0;
    let reserveD = opening?.DieselReserve ?? 0;
    let reserveB = opening?.BenzineReserve ?? 0;
    for (const [key, bucket] of buckets) {
        const excess = Math.max(0, bucket.vehicleUsage - bucket.machineWithdraw);
        const delta = bucket.stockIn - bucket.withdraw - excess;
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
    return {
        Diesel: mainD,
        Benzine: mainB,
        DieselReserve: reserveD,
        BenzineReserve: reserveB,
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
