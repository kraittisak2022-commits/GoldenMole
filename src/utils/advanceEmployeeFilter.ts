import type { Employee } from '../types';

/** ตำแหน่งที่ไม่ให้เลือกในฟอร์มส่งคำขอเบิกเงิน (รวมชื่อเรียกที่ใช้ในระบบ) */
export const ADVANCE_EXCLUDED_POSITIONS = new Set([
    'คนขับรถ',
    'พนักงานขับรถ',
    'รับจ้างรายวัน',
    'รายจ้างรายวัน',
]);

const POSITION_PART_SPLIT = /[,;/|、]/;

export const normalizePositionTitle = (raw: string): string =>
    String(raw ?? '')
        .trim()
        .replace(/\s+/g, ' ');

/** แปลงค่าจาก DB/legacy ให้เป็นรายการสตริง — กัน runtime เมื่อ positions ไม่ใช่ array */
export const coercePositionSources = (
    positions: unknown,
    position?: string | null,
): string[] => {
    const raw: unknown[] = [];

    const pushUnknown = (v: unknown) => {
        if (v == null) return;
        if (Array.isArray(v)) {
            for (const item of v) pushUnknown(item);
            return;
        }
        if (typeof v === 'string') {
            const t = v.trim();
            if (!t) return;
            if (t.startsWith('[')) {
                try {
                    const parsed = JSON.parse(t) as unknown;
                    pushUnknown(parsed);
                    return;
                } catch {
                    /* ใช้สตริงตามเดิม */
                }
            }
            raw.push(t);
            return;
        }
        if (typeof v === 'object') {
            for (const item of Object.values(v as Record<string, unknown>)) {
                pushUnknown(item);
            }
        }
    };

    pushUnknown(positions);
    pushUnknown(position);

    return raw.filter((s): s is string => typeof s === 'string' && s.trim() !== '');
};

/** รวมทุกตำแหน่งจาก `positions` และ `position` (รองรับหลายตำแหน่งในฟิลด์เดียว) */
export const collectEmployeePositionTokens = (e: Employee): string[] => {
    const seen = new Set<string>();
    const out: string[] = [];

    const addRaw = (raw: string | undefined | null) => {
        const trimmed = String(raw ?? '').trim();
        if (!trimmed) return;
        const parts = POSITION_PART_SPLIT.test(trimmed)
            ? trimmed.split(POSITION_PART_SPLIT)
            : [trimmed];
        for (const part of parts) {
            const t = normalizePositionTitle(part);
            if (t && !seen.has(t)) {
                seen.add(t);
                out.push(t);
            }
        }
    };

    for (const p of coercePositionSources(e.positions, e.position)) {
        addRaw(p);
    }

    return out;
};

export const isExcludedPositionToken = (token: string): boolean => {
    const n = normalizePositionTitle(token);
    if (!n) return false;
    return ADVANCE_EXCLUDED_POSITIONS.has(n);
};

/** ซ่อนจากรายการเบิกเมื่อมีอย่างน้อย 1 ตำแหน่งที่อยู่ในรายการยกเว้น */
export const isExcludedFromAdvanceEmployeePicker = (e: Employee): boolean => {
    const tokens = collectEmployeePositionTokens(e);
    if (tokens.length === 0) return false;
    return tokens.some(isExcludedPositionToken);
};

export const employeeEligibleForAdvancePicker = (e: Employee): boolean =>
    !e.inactive && !isExcludedFromAdvanceEmployeePicker(e);

/** @deprecated ใช้ collectEmployeePositionTokens แทน */
export const getEmployeePositions = (e: Employee): string[] =>
    collectEmployeePositionTokens(e);
