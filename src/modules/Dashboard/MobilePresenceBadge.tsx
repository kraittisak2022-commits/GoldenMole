import { useState } from 'react';
import { Smartphone, ChevronDown, Wifi, WifiOff } from 'lucide-react';
import type { MobileDevice } from '../../hooks/useMobilePresence';
import { useShareLocale } from '../Share/shareI18n';

interface MobilePresenceBadgeProps {
    devices: MobileDevice[];
    isOnline: boolean;
    isTracking: boolean;
}

const MobilePresenceBadge = ({ devices, isOnline, isTracking }: MobilePresenceBadgeProps) => {
    const { t, formatTime } = useShareLocale();
    const [expanded, setExpanded] = useState(false);

    return (
        <div className="inline-flex flex-col items-end gap-1.5">
            <button
                type="button"
                onClick={() => devices.length > 0 && setExpanded((v) => !v)}
                className={`inline-flex items-center gap-2 rounded-2xl border px-3 py-2 shadow-sm backdrop-blur-sm transition ${
                    isOnline
                        ? 'border-emerald-300/40 bg-emerald-500/10 text-emerald-100'
                        : 'border-white/10 bg-white/5 text-slate-300'
                }`}
            >
                <div
                    className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-xl ${
                        isOnline ? 'bg-emerald-500/20 text-emerald-300' : 'bg-white/10 text-slate-400'
                    }`}
                >
                    {isOnline ? (
                        <span className="relative flex h-2.5 w-2.5">
                            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-60" />
                            <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-emerald-400" />
                        </span>
                    ) : (
                        <WifiOff size={16} />
                    )}
                </div>

                <div className="min-w-0 text-left">
                    <div className="flex items-center gap-1.5">
                        <Smartphone size={12} className={isOnline ? 'text-emerald-300' : 'text-slate-400'} />
                        <span className={`text-xs font-bold ${isOnline ? 'text-emerald-200' : 'text-slate-300'}`}>
                            {isOnline ? t('mobileOnline', { count: devices.length }) : t('mobileOffline')}
                        </span>
                        {devices.length > 0 && (
                            <ChevronDown
                                size={12}
                                className={`text-emerald-300/70 transition-transform ${expanded ? 'rotate-180' : ''}`}
                            />
                        )}
                    </div>
                    <p className="text-[11px] font-medium leading-tight text-white/50">
                        {isTracking
                            ? isOnline
                                ? t('mobileRealtime')
                                : t('mobileWaiting')
                            : t('mobileConnecting')}
                    </p>
                </div>

                {isOnline && (
                    <Wifi size={14} className="hidden shrink-0 text-emerald-400 sm:block" />
                )}
            </button>

            {expanded && devices.length > 0 && (
                <div className="w-full min-w-[220px] overflow-hidden rounded-xl border border-white/10 bg-slate-900/90 shadow-xl backdrop-blur-md">
                    {devices.map((d) => (
                        <div
                            key={d.id}
                            className="flex items-center justify-between gap-2 border-b border-white/5 px-3 py-2 last:border-0"
                        >
                            <div className="min-w-0">
                                <p className="truncate text-xs font-semibold text-white">{d.username}</p>
                                <p className="truncate text-[10px] text-slate-400">
                                    {d.device}
                                    {d.platform ? ` · ${d.platform}` : ''}
                                </p>
                            </div>
                            <span className="shrink-0 text-[10px] font-mono tabular-nums text-emerald-400">
                                {formatTime(d.onlineSince)}
                            </span>
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
};

export default MobilePresenceBadge;
