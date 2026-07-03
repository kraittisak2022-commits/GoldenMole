import { Radio, RefreshCw, Wifi, WifiOff } from 'lucide-react';
import type { CountRecordSyncSource } from '../../hooks/useCountRecordRealtime';
import type { RealtimeChannelStatus } from '../../services/transactionsRealtimeBus';

interface RealtimeLiveBadgeProps {
    isLive: boolean;
    channelStatus: RealtimeChannelStatus;
    lastSyncAt: number | null;
    syncSource: CountRecordSyncSource | null;
}

const formatSyncTime = (ts: number) =>
    new Date(ts).toLocaleTimeString('th-TH', {
        timeZone: 'Asia/Bangkok',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
    });

const sourceLabel = (source: CountRecordSyncSource | null) => {
    if (source === 'realtime') return 'Realtime';
    if (source === 'poll') return 'Sync';
    if (source === 'local') return 'อัปเดต';
    return null;
};

const RealtimeLiveBadge = ({
    isLive,
    channelStatus,
    lastSyncAt,
    syncSource,
}: RealtimeLiveBadgeProps) => {
    const connected = channelStatus === 'connected';
    const errored = channelStatus === 'error';
    const source = sourceLabel(syncSource);

    return (
        <div className="flex flex-wrap items-center gap-2">
            <span
                className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 ${
                    connected
                        ? 'bg-emerald-50 border-emerald-200 text-emerald-800'
                        : errored
                          ? 'bg-amber-50 border-amber-200 text-amber-800'
                          : 'bg-slate-50 border-slate-200 text-slate-600'
                }`}
            >
                {connected ? (
                    <span className="relative flex h-2 w-2">
                        <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75" />
                        <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500" />
                    </span>
                ) : errored ? (
                    <WifiOff size={12} />
                ) : (
                    <Radio size={12} className="animate-pulse" />
                )}
                <span className="text-[11px] font-extrabold tracking-wide">
                    {connected ? 'LIVE' : errored ? 'POLLING' : 'CONNECTING'}
                </span>
            </span>

            {isLive && (
                <span className="inline-flex items-center gap-1 text-[11px] font-semibold text-slate-500">
                    <Wifi size={12} className="text-indigo-500" />
                    อัปเดตอัตโนมัติจากมือถือ
                </span>
            )}

            {lastSyncAt != null && (
                <span className="inline-flex items-center gap-1 text-[11px] font-medium text-slate-400">
                    <RefreshCw size={11} />
                    {source ? `${source} · ` : ''}
                    {formatSyncTime(lastSyncAt)}
                </span>
            )}
        </div>
    );
};

export default RealtimeLiveBadge;
