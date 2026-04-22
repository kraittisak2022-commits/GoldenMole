import { Transaction } from '../types';
import * as db from './dataService';

const OFFLINE_QUEUE_KEY = 'cm_offline_tx_queue_v1';
const MAX_BACKOFF_MS = 5 * 60 * 1000;
const BASE_BACKOFF_MS = 1500;

export interface OfflineQueueItem {
    id: string;
    tx: Transaction;
    queuedAt: number;
    attempts: number;
    lastError?: string;
    lastErrorType?: 'network' | 'auth' | 'validation' | 'conflict' | 'unknown';
    nextRetryAt?: number;
    conflictWithId?: string;
    conflictPreview?: string;
    conflictRemoteTx?: Transaction;
}

export type SyncState = 'idle' | 'syncing' | 'success' | 'error';

export interface OfflineSyncSnapshot {
    online: boolean;
    queueSize: number;
    syncing: boolean;
    lastState: SyncState;
    lastMessage: string;
    lastSyncedAt?: number;
    failedCount: number;
    conflictCount: number;
}

type Subscriber = (snapshot: OfflineSyncSnapshot) => void;

let queue: OfflineQueueItem[] = [];
let subscribers: Subscriber[] = [];
let isSyncing = false;
let lastState: SyncState = 'idle';
let lastMessage = 'พร้อมใช้งาน';
let lastSyncedAt: number | undefined;

const isBrowser = typeof window !== 'undefined';

const makeSnapshot = (): OfflineSyncSnapshot => ({
    online: isBrowser ? navigator.onLine : true,
    queueSize: queue.length,
    syncing: isSyncing,
    lastState,
    lastMessage,
    lastSyncedAt,
    failedCount: queue.filter(x => x.attempts > 0).length,
    conflictCount: queue.filter(x => !!x.conflictWithId).length,
});

const notify = () => {
    const snapshot = makeSnapshot();
    subscribers.forEach(fn => fn(snapshot));
};

const persistQueue = () => {
    if (!isBrowser) return;
    try {
        window.localStorage.setItem(OFFLINE_QUEUE_KEY, JSON.stringify(queue));
    } catch (err) {
        console.error('persistQueue error', err);
    }
};

const readQueue = () => {
    if (!isBrowser) return;
    try {
        const raw = window.localStorage.getItem(OFFLINE_QUEUE_KEY);
        if (!raw) return;
        const parsed = JSON.parse(raw);
        if (!Array.isArray(parsed)) return;
        queue = parsed
            .filter(x => x && x.tx && typeof x.id === 'string')
            .map(x => ({
                id: String(x.id),
                tx: x.tx as Transaction,
                queuedAt: Number(x.queuedAt) || Date.now(),
                attempts: Number(x.attempts) || 0,
                lastError: typeof x.lastError === 'string' ? x.lastError : undefined,
                lastErrorType: typeof x.lastErrorType === 'string' ? x.lastErrorType : undefined,
                nextRetryAt: Number(x.nextRetryAt) || undefined,
                conflictWithId: typeof x.conflictWithId === 'string' ? x.conflictWithId : undefined,
                conflictPreview: typeof x.conflictPreview === 'string' ? x.conflictPreview : undefined,
                conflictRemoteTx: x.conflictRemoteTx as Transaction | undefined,
            }));
    } catch (err) {
        console.error('readQueue error', err);
    }
};

export const getOfflineSyncSnapshot = (): OfflineSyncSnapshot => makeSnapshot();
export const getOfflineQueue = (): OfflineQueueItem[] => [...queue].sort((a, b) => b.queuedAt - a.queuedAt);

export const subscribeOfflineSync = (listener: Subscriber) => {
    subscribers.push(listener);
    listener(makeSnapshot());
    return () => {
        subscribers = subscribers.filter(fn => fn !== listener);
    };
};

export const initOfflineSync = () => {
    readQueue();
    notify();
};

export const enqueueTransaction = (tx: Transaction) => {
    const existingIdx = queue.findIndex(x => x.tx.id === tx.id);
    if (existingIdx >= 0) {
        queue[existingIdx] = {
            ...queue[existingIdx],
            tx,
            queuedAt: Date.now(),
            conflictWithId: undefined,
            conflictPreview: undefined,
            conflictRemoteTx: undefined,
            lastErrorType: undefined,
            nextRetryAt: undefined,
        };
    } else {
        queue.push({
            id: `q_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
            tx,
            queuedAt: Date.now(),
            attempts: 0,
            conflictWithId: undefined,
            conflictPreview: undefined,
            conflictRemoteTx: undefined,
            lastErrorType: undefined,
            nextRetryAt: undefined,
        });
    }
    persistQueue();
    lastState = 'idle';
    lastMessage = 'บันทึกในเครื่องแล้ว รอซิงก์';
    notify();
};

export const dropOfflineQueueItem = (queueId: string) => {
    queue = queue.filter(item => item.id !== queueId);
    persistQueue();
    notify();
};

export const retryOfflineQueueItemNow = (queueId: string) => {
    queue = queue.map(item => item.id === queueId ? {
        ...item,
        nextRetryAt: undefined,
    } : item);
    persistQueue();
    notify();
};

export const resolveConflictUseServer = (queueId: string) => {
    queue = queue.filter(item => item.id !== queueId);
    persistQueue();
    lastState = 'idle';
    lastMessage = 'ใช้ข้อมูลบนเซิร์ฟเวอร์แล้ว';
    notify();
};

export const resolveConflictUseLocal = async (queueId: string): Promise<boolean> => {
    const item = queue.find(x => x.id === queueId);
    if (!item) return false;
    const ok = await db.saveTransaction(item.tx);
    if (!ok) return false;
    queue = queue.filter(x => x.id !== queueId);
    persistQueue();
    lastState = 'success';
    lastMessage = 'บังคับใช้ข้อมูลในเครื่องสำเร็จ';
    notify();
    return true;
};

const classifyError = (err: unknown): 'network' | 'auth' | 'validation' | 'unknown' => {
    const msg = err instanceof Error ? err.message.toLowerCase() : String(err || '').toLowerCase();
    if (msg.includes('network') || msg.includes('fetch') || msg.includes('timeout') || msg.includes('offline')) return 'network';
    if (msg.includes('auth') || msg.includes('permission') || msg.includes('unauthorized') || msg.includes('forbidden')) return 'auth';
    if (msg.includes('invalid') || msg.includes('constraint') || msg.includes('validation')) return 'validation';
    return 'unknown';
};

const calcNextRetryAt = (attempts: number) => {
    const exp = Math.min(MAX_BACKOFF_MS, BASE_BACKOFF_MS * 2 ** Math.max(0, attempts - 1));
    const jitter = Math.floor(Math.random() * 700);
    return Date.now() + exp + jitter;
};

export const syncOfflineQueue = async (): Promise<OfflineSyncSnapshot> => {
    if (isSyncing) return makeSnapshot();
    if (queue.length === 0) {
        lastState = 'success';
        lastMessage = 'ซิงก์แล้ว';
        notify();
        return makeSnapshot();
    }
    if (isBrowser && !navigator.onLine) {
        lastState = 'error';
        lastMessage = 'ออฟไลน์อยู่ ยังซิงก์ไม่ได้';
        notify();
        return makeSnapshot();
    }

    isSyncing = true;
    lastState = 'syncing';
    lastMessage = 'กำลังซิงก์...';
    notify();

    let successCount = 0;
    const nextQueue: OfflineQueueItem[] = [];
    const remoteTx = await db.fetchTransactions();
    const remoteMap = new Map(remoteTx.map(tx => [tx.id, tx]));

    for (const item of queue) {
        if (item.nextRetryAt && Date.now() < item.nextRetryAt) {
            nextQueue.push(item);
            continue;
        }
        try {
            const remote = remoteMap.get(item.tx.id);
            if (remote) {
                const localSig = JSON.stringify({ ...item.tx, date: String(item.tx.date || '').slice(0, 10) });
                const remoteSig = JSON.stringify({ ...remote, date: String(remote.date || '').slice(0, 10) });
                if (localSig !== remoteSig) {
                    nextQueue.push({
                        ...item,
                        attempts: item.attempts + 1,
                        conflictWithId: remote.id,
                        conflictPreview: `${remote.category}/${remote.subCategory || '-'} ${remote.description || '-'}`,
                        lastError: 'conflict_detected',
                        lastErrorType: 'conflict',
                        conflictRemoteTx: remote,
                        nextRetryAt: undefined,
                    });
                    continue;
                }
            }
            const ok = await db.saveTransaction(item.tx);
            if (ok) {
                successCount += 1;
                continue;
            }
            nextQueue.push({
                ...item,
                attempts: item.attempts + 1,
                lastError: 'saveTransaction returned false',
                lastErrorType: 'unknown',
                conflictWithId: undefined,
                conflictPreview: undefined,
                conflictRemoteTx: undefined,
                nextRetryAt: calcNextRetryAt(item.attempts + 1),
            });
        } catch (err) {
            const errType = classifyError(err);
            nextQueue.push({
                ...item,
                attempts: item.attempts + 1,
                lastError: err instanceof Error ? err.message : 'unknown error',
                lastErrorType: errType,
                conflictWithId: undefined,
                conflictPreview: undefined,
                conflictRemoteTx: undefined,
                nextRetryAt: calcNextRetryAt(item.attempts + 1),
            });
        }
    }

    queue = nextQueue;
    persistQueue();
    isSyncing = false;
    if (queue.length === 0) {
        lastState = 'success';
        lastMessage = successCount > 0 ? `ซิงก์แล้ว ${successCount} รายการ` : 'ซิงก์แล้ว';
        lastSyncedAt = Date.now();
    } else {
        lastState = 'error';
        const conflictCount = queue.filter(x => !!x.conflictWithId).length;
        lastMessage = conflictCount > 0
            ? `พบ conflict ${conflictCount} รายการ และค้าง ${queue.length} รายการ`
            : `ซิงก์ไม่สำเร็จ ค้าง ${queue.length} รายการ`;
    }
    notify();
    return makeSnapshot();
};
