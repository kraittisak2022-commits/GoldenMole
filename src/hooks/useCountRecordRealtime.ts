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
    diffCountRecordActivities,
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
}

export interface UseCountRecordRealtimeResult {
    pulseToken: number;
    lastSyncAt: number | null;
    syncSource: CountRecordSyncSource | null;
    channelStatus: RealtimeChannelStatus;
    activities: CountRecordActivity[];
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
}: UseCountRecordRealtimeOptions): UseCountRecordRealtimeResult {
    const [pulseToken, setPulseToken] = useState(0);
    const [lastSyncAt, setLastSyncAt] = useState<number | null>(null);
    const [syncSource, setSyncSource] = useState<CountRecordSyncSource | null>(null);
    const [channelStatus, setChannelStatus] = useState<RealtimeChannelStatus>('connecting');
    const [activities, setActivities] = useState<CountRecordActivity[]>([]);

    const prevTransactionsRef = useRef<Transaction[]>(transactions);
    const dayKeyRef = useRef(dayKey);

    const pushActivities = useCallback(
        (items: CountRecordActivity[], source: CountRecordSyncSource) => {
            if (items.length === 0) return;
            setActivities((prev) => [...items, ...prev].slice(0, maxActivities));
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
            const items = diffCountRecordActivities(dayKey, prev, transactions, employees);
            if (items.length > 0) pushActivities(items, 'local');
        }
        prevTransactionsRef.current = transactions;
    }, [dayKey, transactions, employees, pushActivities]);

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

    useEffect(() => {
        if (!onRefresh || !dayKey) return;
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
    }, [onRefresh, dayKey, pollIntervalMs]);

    const isLive = channelStatus === 'connected' || channelStatus === 'connecting';

    return {
        pulseToken,
        lastSyncAt,
        syncSource,
        channelStatus,
        activities,
        isLive,
    };
}
