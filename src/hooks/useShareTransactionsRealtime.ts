import { useCallback, useEffect, useState } from 'react';
import { supabase, hasSupabaseConfig } from '../lib/supabase';
import type { Transaction } from '../types';
import * as db from '../services/dataService';
import {
    emitTransactionsRealtime,
    setTransactionsRealtimeStatus,
} from '../services/transactionsRealtimeBus';
import { normalizeDate } from '../utils';

const normalizeTransactionCreatedAt = (tx: Transaction): Transaction => {
    if (tx.createdAt && !Number.isNaN(Date.parse(tx.createdAt))) return tx;
    const baseDate = normalizeDate(tx.date);
    const fallback = Number.isNaN(Date.parse(baseDate))
        ? new Date().toISOString()
        : new Date(`${baseDate}T00:00:00.000Z`).toISOString();
    return { ...tx, createdAt: fallback };
};

export function useShareTransactionsRealtime(enabled: boolean) {
    const [transactions, setTransactions] = useState<Transaction[]>([]);
    const [loading, setLoading] = useState(true);

    const refreshTransactions = useCallback(async () => {
        const latest = await db.fetchTransactions();
        setTransactions(latest.map(normalizeTransactionCreatedAt));
    }, []);

    useEffect(() => {
        if (!enabled) return;
        let cancelled = false;
        void (async () => {
            setLoading(true);
            await refreshTransactions();
            if (!cancelled) setLoading(false);
        })();
        return () => {
            cancelled = true;
        };
    }, [enabled, refreshTransactions]);

    useEffect(() => {
        if (!enabled || !hasSupabaseConfig) return;

        const channel = supabase
            .channel('share-transactions-realtime')
            .on(
                'postgres_changes',
                { event: '*', schema: 'public', table: 'transactions' },
                (payload) => {
                    const eventType = payload.eventType;
                    try {
                        if (eventType === 'DELETE') {
                            const oldRow = payload.old as Record<string, unknown> | undefined;
                            const id = oldRow?.id != null ? String(oldRow.id) : '';
                            if (!id) return;
                            setTransactions((prev) => prev.filter((x) => x.id !== id));
                            emitTransactionsRealtime({ type: 'DELETE', id, at: Date.now() });
                            return;
                        }

                        const row =
                            (eventType === 'INSERT' || eventType === 'UPDATE') && payload.new
                                ? (payload.new as Record<string, unknown>)
                                : null;
                        if (!row || row.id == null) return;
                        const tx = normalizeTransactionCreatedAt(db.transactionFromDbRow(row));

                        setTransactions((prev) => {
                            const i = prev.findIndex((x) => x.id === tx.id);
                            if (i >= 0) {
                                const next = [...prev];
                                next[i] = tx;
                                return next;
                            }
                            return [...prev, tx];
                        });

                        emitTransactionsRealtime({
                            type: eventType === 'INSERT' ? 'INSERT' : 'UPDATE',
                            tx,
                            at: Date.now(),
                        });
                    } catch (e) {
                        console.warn('share transactions realtime merge failed', e);
                    }
                },
            )
            .subscribe((status) => {
                if (status === 'SUBSCRIBED') {
                    setTransactionsRealtimeStatus('connected');
                } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
                    setTransactionsRealtimeStatus('error');
                } else if (status === 'CLOSED') {
                    setTransactionsRealtimeStatus('closed');
                } else {
                    setTransactionsRealtimeStatus('connecting');
                }
            });

        return () => {
            void supabase.removeChannel(channel);
        };
    }, [enabled]);

    return { transactions, loading, refreshTransactions };
}
