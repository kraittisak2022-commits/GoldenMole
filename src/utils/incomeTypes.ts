/** ประเภทรายรับที่เลิกใช้ใน UI (ประวัติเก่ายังอ่านได้) */
const HIDDEN = new Set(['ขายแร่'.toLowerCase()]);

export function visibleIncomeTypes(types: string[] | undefined): string[] {
    return (types || []).filter((t) => !HIDDEN.has(String(t).trim().toLowerCase()));
}
