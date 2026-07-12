import { useMemo, useState } from 'react';
import { Activity, Calendar, Droplets, Link2, Truck, Wallet, TrendingUp, CreditCard, Zap, Settings2 } from 'lucide-react';
import ShareLinkManager from '../Share/ShareLinkManager';
import { useShareLocale } from '../Share/shareI18n';
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
import CountRecordRoundManager from './CountRecordRoundManager';
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
    /** Public share view — mobile-optimized, no admin controls */
    shareMode?: boolean;
    /** Hide income/expense/net profit summary cards */
    hideFinancial?: boolean;
    canManageCountRounds?: boolean;
    onSaveTransaction?: (t: Transaction) => void | Promise<boolean>;
    onDeleteTransaction?: (id: string) => void | Promise<void>;
}

const formatSyncTime = (ts: number, locale: 'th' | 'zh' = 'th') =>
    new Date(ts).toLocaleTimeString(locale === 'zh' ? 'zh-CN' : 'th-TH', {
        timeZone: 'Asia/Bangkok',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
    });

const syncSourceLabel = (source: CountRecordSyncSource | null, t: ReturnType<typeof useShareLocale>['t']) => {
    if (source === 'realtime') return t('syncRealtime');
    if (source === 'poll') return t('syncPoll');
    if (source === 'local') return t('syncLocal');
    return '—';
};

const DashboardV4 = ({
    transactions,
    dateFilter,
    employees = [],
    onRefreshTransactions,
    shareMode = false,
    hideFinancial = true,
    canManageCountRounds = false,
    onSaveTransaction,
    onDeleteTransaction,
}: DashboardV4Props) => {
    const { t, locale, formatDate } = useShareLocale();
    const [selectedDate, setSelectedDate] = useState('');
    const [shareManagerOpen, setShareManagerOpen] = useState(false);
    const [roundManagerKind, setRoundManagerKind] = useState<'all' | 'trip' | 'sand' | null>(null);
    const today = getToday();
    const focusDate = selectedDate || today;
    const isToday = focusDate === today;

    const focusCountRecordStatus = useMemo(
        () => countRecordMenuStatusLabel(focusDate, transactions, locale),
        [focusDate, transactions, locale],
    );

    const tripTotal = useMemo(() => {
        const units = buildCountRecordTripUnits(focusDate, transactions, employees);
        return units.reduce((s, u) => s + u.rounds, 0);
    }, [focusDate, transactions, employees]);

    const sandRounds = useMemo(() => {
        const sand = buildCountRecordSandUnit(focusDate, transactions);
        return sand?.rounds ?? 0;
    }, [focusDate, transactions]);

    const financialSummary = useMemo(() => {
        if (hideFinancial) return null;
        const start = new Date(dateFilter.start);
        const end = new Date(dateFilter.end);
        end.setHours(23, 59, 59, 999);
        const inRange = transactions.filter((t) => {
            const tDate = new Date(t.date);
            return tDate >= start && tDate <= end;
        });
        const totalExpense = inRange.filter((t) => t.type === 'Expense').reduce((s, t) => s + t.amount, 0);
        const totalIncome = inRange.filter((t) => t.type === 'Income').reduce((s, t) => s + t.amount, 0);
        return { totalExpense, totalIncome, net: totalIncome - totalExpense };
    }, [transactions, dateFilter, hideFinancial]);

    const realtime = useCountRecordRealtime({
        dayKey: focusDate,
        transactions,
        employees,
        onRefresh: onRefreshTransactions,
        pollIntervalMs: 12000,
        displayLocale: locale,
    });

    const mobilePresence = useMobilePresence();
    const boardPulse = realtime.pulseToken > 0;
    const showRoundManager =
        canManageCountRounds && !shareMode && !!onSaveTransaction && !!onDeleteTransaction;

    return (
        <div className={`animate-fade-in ${shareMode ? 'space-y-4 portrait:space-y-4 landscape:max-md:space-y-3' : 'space-y-6'}`}>
            {!shareMode && (
                <ShareLinkManager open={shareManagerOpen} onClose={() => setShareManagerOpen(false)} />
            )}

            {showRoundManager && (
                <CountRecordRoundManager
                    open={roundManagerKind !== null}
                    onClose={() => setRoundManagerKind(null)}
                    dayKey={focusDate}
                    transactions={transactions}
                    employees={employees}
                    onSaveTransaction={onSaveTransaction!}
                    onDeleteTransaction={onDeleteTransaction!}
                    filterKind={roundManagerKind === 'trip' || roundManagerKind === 'sand' ? roundManagerKind : undefined}
                />
            )}

            {/* Hero header */}
            <div className={`relative overflow-hidden rounded-[24px] border border-slate-200/80 bg-gradient-to-br from-slate-950 via-slate-900 to-indigo-950 text-white shadow-xl shadow-slate-900/15 ${
                shareMode
                    ? 'px-4 py-4 landscape:max-md:px-3 landscape:max-md:py-3 sm:px-6 sm:py-6'
                    : 'px-5 py-5 sm:px-6 sm:py-6'
            }`}>
                <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top_right,rgba(99,102,241,0.35),transparent_50%)]" />
                <div className="absolute -right-8 -top-8 h-40 w-40 rounded-full bg-indigo-500/20 blur-3xl" />
                <div className="relative flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                    <div className="hidden min-w-0 sm:block">
                        <div className="flex items-center gap-2 text-indigo-200/90">
                            <Activity size={16} />
                            <span className="text-[11px] font-bold uppercase tracking-[0.18em]">{t('operationsMonitor')}</span>
                        </div>
                        <h2 className="mt-1 text-2xl font-bold tracking-tight sm:text-[1.65rem]">{t('realtimeV4')}</h2>
                        <p className="mt-1 max-w-xl text-sm text-slate-300">{t('dashboardSubtitle')}</p>
                        <div className="mt-3 flex flex-wrap items-center gap-2">
                            <label className="relative inline-flex cursor-pointer items-center gap-2 rounded-xl bg-white/10 px-3 py-1.5 text-xs font-semibold text-white/90 ring-1 ring-white/10 backdrop-blur-sm transition hover:bg-white/15">
                                <Calendar size={13} />
                                <span>
                                    {t('viewing')}: {formatDate(focusDate)}
                                </span>
                                {isToday && (
                                    <span className="rounded-md bg-emerald-500/25 px-1.5 py-0.5 text-[10px] font-bold text-emerald-200">
                                        {t('today')}
                                    </span>
                                )}
                                <input
                                    type="date"
                                    value={selectedDate || today}
                                    max={today}
                                    onChange={(e) => setSelectedDate(e.target.value)}
                                    className="absolute inset-0 cursor-pointer opacity-0"
                                    aria-label={t('selectDate')}
                                />
                            </label>
                            {!isToday && (
                                <button
                                    type="button"
                                    onClick={() => setSelectedDate('')}
                                    className="rounded-xl border border-white/20 bg-white/10 px-3 py-1.5 text-xs font-semibold text-white/90 ring-1 ring-white/10 backdrop-blur-sm transition hover:bg-white/15"
                                >
                                    {t('backToToday')}
                                </button>
                            )}
                        </div>
                        {focusCountRecordStatus && (
                            <p className="mt-2 text-sm font-medium text-indigo-200">{focusCountRecordStatus}</p>
                        )}
                    </div>
                    <div className="flex flex-col items-stretch gap-2 sm:items-end">
                        {!shareMode && (
                            <button
                                type="button"
                                onClick={() => setShareManagerOpen(true)}
                                className="inline-flex items-center justify-center gap-2 rounded-xl bg-white/10 px-3 py-2 text-xs font-bold text-white ring-1 ring-white/20 transition hover:bg-white/15 sm:self-end"
                            >
                                <Link2 size={14} />
                                {t('shareLink')}
                            </button>
                        )}
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

            {financialSummary && (
                <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 sm:gap-3">
                    <div className="rounded-2xl border border-rose-100 bg-white p-3 shadow-sm dark:border-rose-500/20 dark:bg-slate-900 sm:p-4">
                        <div className="flex items-center gap-2 text-rose-600 dark:text-rose-400">
                            <CreditCard size={14} />
                            <span className="text-[10px] font-bold uppercase tracking-wide sm:text-xs">{t('expense')}</span>
                        </div>
                        <p className="mt-1 text-lg font-black tabular-nums text-slate-900 dark:text-slate-100 sm:text-xl">
                            {financialSummary.totalExpense.toLocaleString('th-TH')}
                        </p>
                    </div>
                    <div className="rounded-2xl border border-emerald-100 bg-white p-3 shadow-sm dark:border-emerald-500/20 dark:bg-slate-900 sm:p-4">
                        <div className="flex items-center gap-2 text-emerald-600 dark:text-emerald-400">
                            <Wallet size={14} />
                            <span className="text-[10px] font-bold uppercase tracking-wide sm:text-xs">{t('income')}</span>
                        </div>
                        <p className="mt-1 text-lg font-black tabular-nums text-slate-900 dark:text-slate-100 sm:text-xl">
                            {financialSummary.totalIncome.toLocaleString('th-TH')}
                        </p>
                    </div>
                    <div className="col-span-2 rounded-2xl border border-indigo-100 bg-white p-3 shadow-sm dark:border-indigo-500/20 dark:bg-slate-900 sm:col-span-1 sm:p-4">
                        <div className="flex items-center gap-2 text-indigo-600 dark:text-indigo-400">
                            <TrendingUp size={14} />
                            <span className="text-[10px] font-bold uppercase tracking-wide sm:text-xs">{t('netProfit')}</span>
                        </div>
                        <p className={`mt-1 text-lg font-black tabular-nums sm:text-xl ${financialSummary.net >= 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-rose-600 dark:text-rose-400'}`}>
                            {financialSummary.net.toLocaleString('th-TH')}
                        </p>
                    </div>
                </div>
            )}

            {/* Live board */}
            <div
                className={`relative overflow-hidden rounded-[24px] border bg-white shadow-sm transition-all duration-700 dark:bg-slate-900 ${
                    boardPulse
                        ? 'border-indigo-300/80 shadow-xl shadow-indigo-200/40 ring-2 ring-indigo-200/60 dark:border-indigo-500/40 dark:shadow-indigo-950/40 dark:ring-indigo-500/30'
                        : 'border-slate-200/80 shadow-slate-200/40 dark:border-slate-700/60 dark:shadow-slate-950/30'
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
                                    {t('live')}
                                </span>
                            </span>
                            <label className="relative inline-flex cursor-pointer items-center gap-2 rounded-xl bg-white/10 px-2.5 py-1 text-xs font-semibold text-white/90 ring-1 ring-white/10 backdrop-blur-sm transition hover:bg-white/15">
                                <Calendar size={12} />
                                <span>{formatDate(focusDate)}</span>
                                {isToday && (
                                    <span className="rounded-md bg-emerald-500/25 px-1.5 py-0.5 text-[9px] font-bold text-emerald-200">
                                        {t('today')}
                                    </span>
                                )}
                                <input
                                    type="date"
                                    value={selectedDate || today}
                                    max={today}
                                    onChange={(e) => setSelectedDate(e.target.value)}
                                    className="absolute inset-0 cursor-pointer opacity-0"
                                    aria-label={t('selectDate')}
                                />
                            </label>
                            {!isToday && (
                                <button
                                    type="button"
                                    onClick={() => setSelectedDate('')}
                                    className="rounded-xl border border-white/20 bg-white/10 px-2 py-1 text-[10px] font-semibold text-white/90 ring-1 ring-white/10 backdrop-blur-sm transition hover:bg-white/15"
                                >
                                    {t('backToToday')}
                                </button>
                            )}
                            {boardPulse && <Zap size={14} className="text-amber-300 animate-pulse" />}
                        </div>

                        <div className="flex flex-wrap items-center gap-2">
                            {showRoundManager && (
                                <button
                                    type="button"
                                    onClick={() => setRoundManagerKind('all')}
                                    className="inline-flex items-center gap-1.5 rounded-xl bg-amber-500/15 px-2.5 py-1.5 text-xs font-bold text-amber-100 ring-1 ring-amber-400/30 transition hover:bg-amber-500/25"
                                >
                                    <Settings2 size={13} className="text-amber-300" />
                                    จัดการรอบ
                                </button>
                            )}
                            <span className="inline-flex items-center gap-1.5 rounded-xl bg-blue-500/15 px-2.5 py-1.5 text-xs font-bold text-blue-100 ring-1 ring-blue-400/25">
                                <Truck size={13} className="text-blue-300" />
                                {formatDashboardMetric(tripTotal)} {t('tripUnit')}
                            </span>
                            <span className="inline-flex items-center gap-1.5 rounded-xl bg-pink-500/15 px-2.5 py-1.5 text-xs font-bold text-pink-100 ring-1 ring-pink-400/25">
                                <Droplets size={13} className="text-pink-300" />
                                {formatDashboardMetric(sandRounds)} {t('roundUnit')}
                            </span>
                            {realtime.lastSyncAt != null && (
                                <span className="inline-flex flex-col items-end rounded-xl bg-white/5 px-2.5 py-1.5 text-right ring-1 ring-white/10">
                                    <span className="text-[9px] font-bold uppercase tracking-wide text-slate-400">
                                        {syncSourceLabel(realtime.syncSource, t)}
                                    </span>
                                    <span className="font-mono text-[11px] font-semibold tabular-nums text-slate-200">
                                        {formatSyncTime(realtime.lastSyncAt, locale)}
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
                        shareMode={shareMode}
                        onManageRounds={showRoundManager ? (kind) => setRoundManagerKind(kind) : undefined}
                    />
                </div>

                {realtime.activities.length > 0 && (
                    <div className={`border-t border-slate-100 bg-slate-50/40 dark:border-slate-800 dark:bg-slate-950/40 ${shareMode ? 'p-3 landscape:max-md:p-2.5 sm:p-5' : 'p-4 sm:p-5'}`}>
                        <CountRecordActivityFeed activities={realtime.activities} compact={shareMode} />
                    </div>
                )}
            </div>
        </div>
    );
};

export default DashboardV4;
