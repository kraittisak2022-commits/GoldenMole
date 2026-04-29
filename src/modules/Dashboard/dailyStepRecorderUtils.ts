import { Transaction } from '../../types';
import { normalizeDate } from '../../utils';

const toTimeOrNull = (value: string | undefined): number | null => {
    if (!value) return null;
    const t = Date.parse(value);
    return Number.isNaN(t) ? null : t;
};

export const getTransactionRecencyScore = (
    tx: Transaction,
    _dayItems: Transaction[],
    idxFallback = -1,
): number => {
    const createdAtMs = toTimeOrNull(tx.createdAt);
    if (createdAtMs != null) return createdAtMs;
    const dayMs = toTimeOrNull(`${normalizeDate(tx.date)}T00:00:00.000Z`);
    if (dayMs != null) return dayMs + Math.max(0, idxFallback);
    return idxFallback;
};

export const pickLatestByDayOrder = <T extends Transaction>(items: T[], dayItems: Transaction[]): T | null => {
    if (items.length === 0) return null;
    const lastIndexById = new Map<string, number>();
    dayItems.forEach((tx, idx) => {
        lastIndexById.set(tx.id, idx);
    });
    return items.reduce((latest, current) => {
        const latestIdx = lastIndexById.get(latest.id) ?? -1;
        const currentIdx = lastIndexById.get(current.id) ?? -1;
        const latestScore = getTransactionRecencyScore(latest, dayItems, latestIdx);
        const currentScore = getTransactionRecencyScore(current, dayItems, currentIdx);
        if (currentScore === latestScore) return currentIdx >= latestIdx ? current : latest;
        return currentScore > latestScore ? current : latest;
    });
};

type AnySandTx = Transaction & {
    sandBatchId?: string;
    drumsObtained?: number;
    sandHomeBatchUsages?: Array<{ batchId?: string; sourceDate?: string; drums?: number }>;
};

export interface BatchStockEntry {
    batchId: string;
    sourceDate: string;
    obtained: number;
    used: number;
    available: number;
}

/**
 * Compute remaining sand stock per Lot/Batch from a list of DailyLog/Sand transactions.
 *
 * Important: a single day's home washing may be persisted on more than one sand
 * transaction (e.g. when both sand1 and sand2 machines are saved together). The
 * usages array attached to each record is identical, so naively summing the drums
 * across all sand records would double-count and incorrectly exhaust a batch. To
 * stay correct on both new and legacy data we collapse usages by
 * (homeDate, batchId, sourceDate) using max() before accumulating.
 */
export const computeBatchStockSummary = (sandTxs: AnySandTx[]): BatchStockEntry[] => {
    const summary = new Map<string, { sourceDate: string; obtained: number; used: number }>();
    const usageByDay = new Map<string, Map<string, number>>();
    sandTxs.forEach((t) => {
        const homeDate = normalizeDate(t.date);
        const usages = Array.isArray(t.sandHomeBatchUsages) ? t.sandHomeBatchUsages : [];
        if (usages.length === 0) return;
        const dayBucket = usageByDay.get(homeDate) || new Map<string, number>();
        usages.forEach((u) => {
            const batchId = String(u?.batchId || '').trim();
            const sourceDate = String(u?.sourceDate || '').trim();
            const drums = Math.max(0, Number(u?.drums || 0));
            if (!batchId || !sourceDate || drums <= 0) return;
            const key = `${batchId}|${sourceDate}`;
            dayBucket.set(key, Math.max(dayBucket.get(key) || 0, drums));
        });
        usageByDay.set(homeDate, dayBucket);
    });
    sandTxs.forEach((t) => {
        const batchId = String(t.sandBatchId || '').trim();
        if (!batchId) return;
        const sourceDate = normalizeDate(t.date);
        const rec = summary.get(batchId) || { sourceDate, obtained: 0, used: 0 };
        rec.obtained = Math.max(rec.obtained, Number(t.drumsObtained || 0));
        summary.set(batchId, rec);
    });
    usageByDay.forEach((dayBucket) => {
        dayBucket.forEach((drums, key) => {
            const [batchId, sourceDate] = key.split('|');
            const rec = summary.get(batchId) || { sourceDate, obtained: 0, used: 0 };
            rec.used += drums;
            summary.set(batchId, rec);
        });
    });
    return Array.from(summary.entries())
        .map(([batchId, v]) => ({ batchId, ...v, available: Math.max(0, v.obtained - v.used) }))
        .sort((a, b) => a.sourceDate.localeCompare(b.sourceDate));
};
