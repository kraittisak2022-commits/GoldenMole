import { normalizeDate } from '../../utils';
import type { Transaction } from '../../types';

const toTimeOrNull = (value: string | undefined): number | null => {
    if (!value) return null;
    const t = Date.parse(value);
    return Number.isNaN(t) ? null : t;
};

export const getTransactionRecencyScore = (tx: Transaction, dayItems: Transaction[], idxFallback = -1): number => {
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
