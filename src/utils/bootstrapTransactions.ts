import type { Transaction } from '../types';

const SAMPLE_TRANSACTION_IDS = new Set(['1', '2', '3']);

/** ชุดตัวอย่าง 3 แถวที่ใส่ตอนโหลดไม่สำเร็จ — ไม่ใช่ข้อมูลจริง */
export function isSampleTransactionList(rows: Transaction[]): boolean {
    if (rows.length === 0 || rows.length > SAMPLE_TRANSACTION_IDS.size) return false;
    return rows.every((row) => SAMPLE_TRANSACTION_IDS.has(row.id));
}

export type TransactionFetchOutcome = Transaction[] | 'failed';

/**
 * เลือกชุดรายการที่จะแสดงหลังโหลดครั้งแรก
 * - ดึงสำเร็จ (รวมฐานว่างจริง) → ใช้ผลดึง และบันทึกแคช
 * - ดึงไม่ทันหรือผิดพลาด → คงแคชที่เป็นข้อมูลจริง และไม่เขียนทับแคช
 */
export function pickLoadedTransactions(
    fetched: TransactionFetchOutcome,
    cached: Transaction[] | null,
): { rows: Transaction[]; persist: boolean } {
    if (Array.isArray(fetched)) {
        return { rows: fetched, persist: true };
    }
    if (cached && !isSampleTransactionList(cached)) {
        return { rows: cached, persist: false };
    }
    return { rows: cached ?? [], persist: false };
}
