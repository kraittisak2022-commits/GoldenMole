import type { Transaction } from '../types';

export type TransactionsRealtimeEvent =
    | { type: 'INSERT' | 'UPDATE'; tx: Transaction; at: number }
    | { type: 'DELETE'; id: string; at: number };

export type RealtimeChannelStatus = 'connecting' | 'connected' | 'error' | 'closed';

type Listener = (event: TransactionsRealtimeEvent) => void;
type StatusListener = (status: RealtimeChannelStatus) => void;

let listeners: Listener[] = [];
let statusListeners: StatusListener[] = [];
let lastStatus: RealtimeChannelStatus = 'connecting';

export const emitTransactionsRealtime = (event: TransactionsRealtimeEvent) => {
    listeners.forEach((fn) => fn(event));
};

export const subscribeTransactionsRealtime = (listener: Listener) => {
    listeners.push(listener);
    return () => {
        listeners = listeners.filter((fn) => fn !== listener);
    };
};

export const setTransactionsRealtimeStatus = (status: RealtimeChannelStatus) => {
    lastStatus = status;
    statusListeners.forEach((fn) => fn(status));
};

export const subscribeTransactionsRealtimeStatus = (listener: StatusListener) => {
    statusListeners.push(listener);
    listener(lastStatus);
    return () => {
        statusListeners = statusListeners.filter((fn) => fn !== listener);
    };
};

export const getTransactionsRealtimeStatus = () => lastStatus;
