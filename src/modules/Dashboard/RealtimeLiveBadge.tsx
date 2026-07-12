import { Radio, RefreshCw, Wifi, WifiOff, Zap } from 'lucide-react';
import type { CountRecordSyncSource } from '../../hooks/useCountRecordRealtime';
import type { RealtimeChannelStatus } from '../../services/transactionsRealtimeBus';
import { useShareLocale } from '../Share/shareI18n';

interface RealtimeLiveBadgeProps {
    isLive: boolean;
    channelStatus: RealtimeChannelStatus;
    lastSyncAt: number | null;
    syncSource: CountRecordSyncSource | null;
}

const RealtimeLiveBadge = ({
    isLive,
    channelStatus,
    lastSyncAt,
    syncSource,
}: RealtimeLiveBadgeProps) => {
    const { t, formatTime } = useShareLocale();
    const connected = channelStatus === 'connected';
    const errored = channelStatus === 'error';

    const statusLabel = connected ? t('statusLive') : errored ? t('statusPolling') : t('statusConnecting');
    const statusHint = connected ? t('realtimeConnected') : errored ? t('pollFallback') : t('connectingChannel');

    const sourceLabel = (source: CountRecordSyncSource | null) => {
        if (source === 'realtime') return t('syncRealtime');
        if (source === 'poll') return t('syncPoll');
        if (source === 'local') return t('syncLocal');
        return '—';
    };

    return (
        <div className="inline-flex flex-col items-end gap-1.5 sm:items-end">
            <div className="inline-flex items-center gap-2 rounded-2xl border border-slate-200/80 bg-white/90 backdrop-blur-sm px-3 py-2 shadow-sm shadow-slate-200/50 dark:border-slate-700/60 dark:bg-slate-900/80 dark:shadow-slate-950/50">
                <div
                    className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-xl ${
                        connected
                            ? 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'
                            : errored
                              ? 'bg-amber-500/10 text-amber-600 dark:text-amber-400'
                              : 'bg-slate-100 text-slate-500 dark:bg-slate-800 dark:text-slate-400'
                    }`}
                >
                    {connected ? (
                        <span className="relative flex h-2.5 w-2.5">
                            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-60" />
                            <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-emerald-500" />
                        </span>
                    ) : errored ? (
                        <WifiOff size={16} />
                    ) : (
                        <Radio size={16} className="animate-pulse" />
                    )}
                </div>

                <div className="min-w-0 text-left">
                    <div className="flex items-center gap-1.5">
                        <span
                            className={`text-xs font-bold uppercase tracking-[0.14em] ${
                                connected ? 'text-emerald-700 dark:text-emerald-300' : errored ? 'text-amber-700 dark:text-amber-300' : 'text-slate-600 dark:text-slate-300'
                            }`}
                        >
                            {statusLabel}
                        </span>
                        {isLive && connected && <Zap size={11} className="text-emerald-500 dark:text-emerald-400" />}
                    </div>
                    <p className="text-[11px] font-medium text-slate-500 leading-tight dark:text-slate-400">{statusHint}</p>
                </div>

                {lastSyncAt != null && (
                    <div className="hidden sm:block h-8 w-px bg-slate-200 shrink-0 dark:bg-slate-700" />
                )}

                {lastSyncAt != null && (
                    <div className="hidden sm:block text-right min-w-[88px]">
                        <p className="text-[10px] font-semibold uppercase tracking-wide text-slate-400 dark:text-slate-500">
                            {sourceLabel(syncSource)}
                        </p>
                        <p className="text-xs font-mono font-semibold tabular-nums text-slate-700 dark:text-slate-200">
                            {formatTime(lastSyncAt)}
                        </p>
                    </div>
                )}
            </div>

            {lastSyncAt != null && (
                <p className="flex items-center gap-1 text-[10px] font-medium text-slate-400 dark:text-slate-500 sm:hidden">
                    <RefreshCw size={10} />
                    <Wifi size={10} className="text-indigo-400" />
                    {sourceLabel(syncSource)} · {formatTime(lastSyncAt)}
                </p>
            )}
        </div>
    );
};

export default RealtimeLiveBadge;
