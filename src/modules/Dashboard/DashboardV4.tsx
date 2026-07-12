import { useMemo, useState } from 'react';
import { Activity, Calendar, Droplets, Truck, Zap } from 'lucide-react';
import type { CountRecordSyncSource } from '../../hooks/useCountRecordRealtime';
import { Transaction, Employee, AppSettings } from '../../types';
import { getToday } from '../../utils';
import { useCountRecordRealtime } from '../../hooks/useCountRecordRealtime';
import { useMobilePresence } from '../../hooks/useMobilePresence';
import CountRecordOverview from './CountRecordOverview';
import CountRecordActivityFeed from './CountRecordActivityFeed';
import RealtimeLiveBadge from './RealtimeLiveBadge';
import MobilePresenceBadge from './MobilePresenceBadge';
import LiveIncrementOverlay from './LiveIncrementOverlay';
import {
    buildCountRecordSandUnit,
    buildCountRecordTripUnits,
    countRecordMenuStatusLabel,
    formatDashboardMetric,
} from './countRecordUtils';

interface DashboardV4Props {
    transactions: Transaction[];
    dateFilter: { start: string; end: string };
    employees?: Employee[];
    settings?: AppSettings;
    onRefreshTransactions?: () => void | Promise<void>;
}

const formatThaiDate = (d: string) =>
    new Date(d + 'T12:00:00+07:00').toLocaleDateString('th-TH', {
        timeZone: 'Asia/Bangkok',
        weekday: 'short',
        day: 'numeric',
        month: 'short',
        year: '2-digit',
    });

const formatSyncTime = (ts: number) =>
    new Date(ts).toLocaleTimeString('th-TH', {
        timeZone: 'Asia/Bangkok',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
    });

const syncSourceLabel = (source: CountRecordSyncSource | null) => {
    if (source === 'realtime') return 'Realtime';
    if (source === 'poll') return 'Auto-sync';
    if (source === 'local') return 'Updated';
    return '—';
};

const DashboardV4 = ({ transactions, employees = [], onRefreshTransactions }: DashboardV4Props) => {
    const [selectedDate, setSelectedDate] = useState('');
    const today = getToday();
    const focusDate = selectedDate || today;
    const isToday = focusDate === today;

    const focusCountRecordStatus = useMemo(
        () => countRecordMenuStatusLabel(focusDate, transactions),
        [focusDate, transactions],
    );

    const tripTotal = useMemo(() => {
        const units = buildCountRecordTripUnits(focusDate, transactions, employees);
        return units.reduce((s, u) => s + u.rounds, 0);
    }, [focusDate, transactions, employees]);

    const sandRounds = useMemo(() => {
        const sand = buildCountRecordSandUnit(focusDate, transactions);
        return sand?.rounds ?? 0;
    }, [focusDate, transactions]);

    const realtime = useCountRecordRealtime({
        dayKey: focusDate,
        transactions,
        employees,
        onRefresh: onRefreshTransactions,
        pollIntervalMs: 12000,
    });

    const mobilePresence = useMobilePresence();
    const boardPulse = realtime.pulseToken > 0;

    return (
        <div className="space-y-6 animate-fade-in">
            {/* Hero header */}
            <div className="relative overflow-hidden rounded-[24px] border border-slate-200/80 bg-gradient-to-br from-slate-950 via-slate-900 to-indigo-950 px-5 py-5 sm:px-6 sm:py-6 text-white shadow-xl shadow-slate-900/15">
                <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top_right,rgba(99,102,241,0.35),transparent_50%)]" />
                <div className="absolute -right-8 -top-8 h-40 w-40 rounded-full bg-indigo-500/20 blur-3xl" />
                <div className="relative flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                    <div className="min-w-0">
                        <div className="flex items-center gap-2 text-indigo-200/90">
                            <Activity size={16} />
                            <span className="text-[11px] font-bold uppercase tracking-[0.18em]">Operations Monitor</span>
                        </div>
                        <h2 className="mt-1 text-2xl font-bold tracking-tight sm:text-[1.65rem]">Real-time V.4</h2>
                        <p className="mt-1 max-w-xl text-sm text-slate-300">
                            ติดตามการนับเที่ยวรถและรอบร่อนทรายจากแอปมือถือแบบเรียลไทม์
                        </p>
                        <p className="mt-3 inline-flex items-center gap-2 rounded-xl bg-white/10 px-3 py-1.5 text-xs font-semibold text-white/90 ring-1 ring-white/10 backdrop-blur-sm">
                            <Calendar size={13} />
                            กำลังดู: {formatThaiDate(focusDate)}
                            {isToday && (
                                <span className="rounded-md bg-emerald-500/25 px-1.5 py-0.5 text-[10px] font-bold text-emerald-200">
                                    วันนี้
                                </span>
                            )}
                        </p>
                        {focusCountRecordStatus && (
                            <p className="mt-2 text-sm font-medium text-indigo-200">{focusCountRecordStatus}</p>
                        )}
                    </div>
                    <div className="flex flex-col items-stretch gap-2 sm:items-end">
                        <MobilePresenceBadge
                            devices={mobilePresence.devices}
                            isOnline={mobilePresence.isOnline}
                            isTracking={mobilePresence.isTracking}
                        />
                        <RealtimeLiveBadge
                            isLive={realtime.isLive}
                            channelStatus={realtime.channelStatus}
                            lastSyncAt={realtime.lastSyncAt}
                            syncSource={realtime.syncSource}
                        />
                    </div>
                </div>
            </div>

            {/* Date selector */}
            <div className="rounded-2xl border border-slate-200/80 bg-white p-4 shadow-sm shadow-slate-200/30">
                <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-4">
                    <label className="flex items-center gap-2 text-sm font-semibold text-slate-700">
                        <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-indigo-50 text-indigo-600">
                            <Calendar size={15} />
                        </span>
                        เลือกวันที่
                    </label>
                    <div className="flex flex-col gap-2 xs:flex-row w-full sm:w-auto">
                        <input
                            type="date"
                            value={selectedDate || today}
                            max={today}
                            onChange={(e) => setSelectedDate(e.target.value)}
                            className="w-full sm:w-auto rounded-xl border border-slate-200 bg-slate-50/50 px-3 py-2.5 text-sm font-medium text-slate-700 outline-none transition focus:border-indigo-300 focus:bg-white focus:ring-2 focus:ring-indigo-100"
                        />
                        {!isToday && (
                            <button
                                type="button"
                                onClick={() => setSelectedDate('')}
                                className="rounded-xl border border-indigo-200 bg-indigo-50 px-3 py-2.5 text-sm font-semibold text-indigo-700 transition hover:bg-indigo-100"
                            >
                                กลับวันนี้
                            </button>
                        )}
                    </div>
                    <p className="text-xs font-medium text-slate-400 sm:ml-auto">
                        แสดงเฉพาะ {formatThaiDate(focusDate)}
                    </p>
                </div>
            </div>

            {/* Live board */}
            <div
                className={`relative overflow-hidden rounded-[24px] border bg-white shadow-sm transition-all duration-700 ${
                    boardPulse
                        ? 'border-indigo-300/80 shadow-xl shadow-indigo-200/40 ring-2 ring-indigo-200/60'
                        : 'border-slate-200/80 shadow-slate-200/40'
                }`}
            >
                <div className="relative overflow-hidden border-b border-white/10 bg-gradient-to-r from-slate-900 via-indigo-950 to-slate-900 px-4 py-3.5 sm:px-5">
                    <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_left,rgba(99,102,241,0.25),transparent_55%)]" />
                    <div className="relative flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                        <div className="flex flex-wrap items-center gap-2 sm:gap-3">
                            <span className="inline-flex items-center gap-2 rounded-full bg-emerald-500/15 px-2.5 py-1 ring-1 ring-emerald-400/30">
                                <span className="relative flex h-2 w-2">
                                    <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-70" />
                                    <span className="relative inline-flex h-2 w-2 rounded-full bg-emerald-400" />
                                </span>
                                <span className="text-[10px] font-black uppercase tracking-[0.2em] text-emerald-300">
                                    Live
                                </span>
                            </span>
                            <span className="text-sm font-bold text-white">{formatThaiDate(focusDate)}</span>
                            {boardPulse && <Zap size={14} className="text-amber-300 animate-pulse" />}
                        </div>

                        <div className="flex flex-wrap items-center gap-2">
                            <span className="inline-flex items-center gap-1.5 rounded-xl bg-blue-500/15 px-2.5 py-1.5 text-xs font-bold text-blue-100 ring-1 ring-blue-400/25">
                                <Truck size={13} className="text-blue-300" />
                                {formatDashboardMetric(tripTotal)} เที่ยว
                            </span>
                            <span className="inline-flex items-center gap-1.5 rounded-xl bg-pink-500/15 px-2.5 py-1.5 text-xs font-bold text-pink-100 ring-1 ring-pink-400/25">
                                <Droplets size={13} className="text-pink-300" />
                                {formatDashboardMetric(sandRounds)} รอบ
                            </span>
                            {realtime.lastSyncAt != null && (
                                <span className="inline-flex flex-col items-end rounded-xl bg-white/5 px-2.5 py-1.5 text-right ring-1 ring-white/10">
                                    <span className="text-[9px] font-bold uppercase tracking-wide text-slate-400">
                                        {syncSourceLabel(realtime.syncSource)}
                                    </span>
                                    <span className="font-mono text-[11px] font-semibold tabular-nums text-slate-200">
                                        {formatSyncTime(realtime.lastSyncAt)}
                                    </span>
                                </span>
                            )}
                        </div>
                    </div>
                </div>

                <div className="relative p-4 sm:p-5">
                    <LiveIncrementOverlay increments={realtime.increments} />
                    <CountRecordOverview
                        dayKey={focusDate}
                        transactions={transactions}
                        employees={employees}
                        pulseToken={realtime.pulseToken}
                        increments={realtime.increments}
                    />
                </div>

                {realtime.activities.length > 0 && (
                    <div className="border-t border-slate-100 bg-slate-50/40 p-4 sm:p-5">
                        <CountRecordActivityFeed activities={realtime.activities} />
                    </div>
                )}
            </div>
        </div>
    );
};

export default DashboardV4;
