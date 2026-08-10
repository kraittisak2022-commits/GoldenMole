import { useCallback, useEffect, useRef, useState } from 'react';
import type { Employee, Transaction } from '../types';
import {
    subscribeTransactionsRealtime,
    subscribeTransactionsRealtimeStatus,
    type RealtimeChannelStatus,
    type TransactionsRealtimeEvent,
} from '../services/transactionsRealtimeBus';
import {
    CountRecordActivity,
    CountRecordIncrement,
    diffCountRecordActivities,
    diffCountRecordIncrements,
    isCountRecordRelatedTransaction,
} from '../modules/Dashboard/countRecordUtils';

export type CountRecordSyncSource = 'realtime' | 'poll' | 'local';

export interface UseCountRecordRealtimeOptions {
    dayKey: string;
    transactions: Transaction[];
    employees?: Employee[];
    onRefresh?: () => void | Promise<void>;
    pollIntervalMs?: number;
    maxActivities?: number;
    displayLocale?: 'th' | 'zh';
}

export interface UseCountRecordRealtimeResult {
    pulseToken: number;
    lastSyncAt: number | null;
    syncSource: CountRecordSyncSource | null;
    channelStatus: RealtimeChannelStatus;
    activities: CountRecordActivity[];
    increments: CountRecordIncrement[];
    isLive: boolean;
}

const defaultEmployees: Employee[] = [];

export function useCountRecordRealtime({
    dayKey,
    transactions,
    employees = defaultEmployees,
    onRefresh,
    pollIntervalMs = 12000,
    maxActivities = 12,
    displayLocale = 'th',
}: UseCountRecordRealtimeOptions): UseCountRecordRealtimeResult {
    const [pulseToken, setPulseToken] = useState(0);
    const [lastSyncAt, setLastSyncAt] = useState<number | null>(null);
    const [syncSource, setSyncSource] = useState<CountRecordSyncSource | null>(null);
    const [channelStatus, setChannelStatus] = useState<RealtimeChannelStatus>('connecting');
    const [activities, setActivities] = useState<CountRecordActivity[]>([]);
    const [increments, setIncrements] = useState<CountRecordIncrement[]>([]);

    const prevTransactionsRef = useRef<Transaction[]>(transactions);
    const dayKeyRef = useRef(dayKey);

    const pushActivities = useCallback(
        (items: CountRecordActivity[], incrementItems: CountRecordIncrement[], source: CountRecordSyncSource) => {
            if (items.length === 0 && incrementItems.length === 0) return;
            if (items.length > 0) {
                setActivities((prev) => [...items, ...prev].slice(0, maxActivities));
            }
            if (incrementItems.length > 0) {
                setIncrements((prev) => [...incrementItems, ...prev].slice(0, maxActivities));
            }
            setPulseToken((t) => t + 1);
            setLastSyncAt(Date.now());
            setSyncSource(source);
        },
        [maxActivities],
    );

    useEffect(() => {
        dayKeyRef.current = dayKey;
    }, [dayKey]);

    useEffect(() => {
        if (!dayKey) return;
        const prev = prevTransactionsRef.current;
        if (prev !== transactions) {
            const items = diffCountRecordActivities(dayKey, prev, transactions, employees, displayLocale);
            const incItems = diffCountRecordIncrements(dayKey, prev, transactions, employees);
            if (items.length > 0 || incItems.length > 0) pushActivities(items, incItems, 'local');
        }
        prevTransactionsRef.current = transactions;
    }, [dayKey, transactions, employees, pushActivities, displayLocale]);

    useEffect(() => subscribeTransactionsRealtimeStatus(setChannelStatus), []);

    useEffect(() => {
        const onEvent = (event: TransactionsRealtimeEvent) => {
            const key = dayKeyRef.current;
            if (!key) return;

            if (event.type === 'DELETE') {
                setLastSyncAt(event.at);
                setSyncSource('realtime');
                return;
            }

            const txDate = String(event.tx.date ?? '').trim().slice(0, 10);
            if (txDate !== key || !isCountRecordRelatedTransaction(event.tx)) return;

            setLastSyncAt(event.at);
            setSyncSource('realtime');
            setPulseToken((t) => t + 1);
        };
        return subscribeTransactionsRealtime(onEvent);
    }, []);

    // Poll only when Realtime is down — avoids full-table refetch every 12s while live.
    useEffect(() => {
        if (!onRefresh || !dayKey) return;
        if (channelStatus === 'connected' || channelStatus === 'connecting') return;
        let disposed = false;

        const tick = async () => {
            try {
                await onRefresh();
                if (disposed) return;
                setLastSyncAt(Date.now());
                setSyncSource('poll');
            } catch {
                /* ignore poll errors */
            }
        };

        void tick();
        const timer = window.setInterval(() => void tick(), pollIntervalMs);
        return () => {
            disposed = true;
            window.clearInterval(timer);
        };
    }, [onRefresh, dayKey, pollIntervalMs, channelStatus]);

    const isLive = channelStatus === 'connected' || channelStatus === 'connecting';

    return {
        pulseToken,
        lastSyncAt,
        syncSource,
        channelStatus,
        activities,
        increments,
        isLive,
    };
}
