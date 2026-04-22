import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('./dataService', () => ({
    saveTransaction: vi.fn(async () => true),
    fetchTransactions: vi.fn(async () => []),
}));

import * as db from './dataService';
import {
    dropOfflineQueueItem,
    enqueueTransaction,
    getOfflineQueue,
    initOfflineSync,
    retryOfflineQueueItemNow,
    resolveConflictUseServer,
    syncOfflineQueue,
} from './offlineSync';

describe('offlineSync', () => {
    beforeEach(() => {
        window.localStorage.clear();
        vi.clearAllMocks();
        initOfflineSync();
        getOfflineQueue().forEach(x => dropOfflineQueueItem(x.id));
    });

    it('queues transaction when offline path used', () => {
        enqueueTransaction({
            id: 'tx-1',
            date: '2026-01-01',
            type: 'Expense',
            category: 'Fuel',
            description: 'offline fuel',
            amount: 100,
        });
        expect(getOfflineQueue().length).toBe(1);
    });

    it('removes queue item when resolve use server', () => {
        enqueueTransaction({
            id: 'tx-2',
            date: '2026-01-01',
            type: 'Expense',
            category: 'Fuel',
            description: 'conflict item',
            amount: 120,
        });
        const item = getOfflineQueue()[0];
        resolveConflictUseServer(item.id);
        expect(getOfflineQueue().length).toBe(0);
    });

    it('syncs queue successfully', async () => {
        enqueueTransaction({
            id: 'tx-3',
            date: '2026-01-01',
            type: 'Income',
            category: 'Income',
            description: 'income',
            amount: 220,
        });
        const snap = await syncOfflineQueue();
        expect(db.saveTransaction).toHaveBeenCalled();
        expect(snap.queueSize).toBe(0);
    });

    it('marks retry now for queued item', () => {
        enqueueTransaction({
            id: 'tx-4',
            date: '2026-01-01',
            type: 'Expense',
            category: 'Fuel',
            description: 'retry me',
            amount: 99,
        });
        const item = getOfflineQueue()[0];
        retryOfflineQueueItemNow(item.id);
        const next = getOfflineQueue().find(x => x.id === item.id);
        expect(next?.nextRetryAt).toBeUndefined();
    });
});
