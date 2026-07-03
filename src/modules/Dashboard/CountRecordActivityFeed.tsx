import { Activity, Droplets, Trash2, Truck } from 'lucide-react';
import type { CountRecordActivity } from './countRecordUtils';

interface CountRecordActivityFeedProps {
    activities: CountRecordActivity[];
    compact?: boolean;
}

const kindMeta: Record<
    CountRecordActivity['kind'],
    { icon: typeof Truck; dot: string; line: string; bg: string; text: string }
> = {
    trip: {
        icon: Truck,
        dot: 'bg-blue-500 ring-blue-100',
        line: 'from-blue-400/40',
        bg: 'bg-blue-50/90',
        text: 'text-blue-950',
    },
    sand: {
        icon: Droplets,
        dot: 'bg-pink-500 ring-pink-100',
        line: 'from-pink-400/40',
        bg: 'bg-pink-50/90',
        text: 'text-pink-950',
    },
    delete: {
        icon: Trash2,
        dot: 'bg-rose-500 ring-rose-100',
        line: 'from-rose-400/40',
        bg: 'bg-rose-50/90',
        text: 'text-rose-950',
    },
};

const formatActivityTime = (at: number) =>
    new Date(at).toLocaleTimeString('th-TH', {
        timeZone: 'Asia/Bangkok',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
    });

const CountRecordActivityFeed = ({ activities, compact = false }: CountRecordActivityFeedProps) => {
    if (activities.length === 0) return null;

    return (
        <div
            className={`overflow-hidden rounded-2xl border border-slate-200/80 bg-gradient-to-b from-white to-slate-50/80 ${
                compact ? '' : 'shadow-sm shadow-slate-200/40'
            }`}
        >
            <div className="flex items-center justify-between gap-2 border-b border-slate-100 px-4 py-3 bg-white/70">
                <div className="flex items-center gap-2">
                    <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-indigo-500/10 text-indigo-600">
                        <Activity size={14} />
                    </span>
                    <div>
                        <p className="text-xs font-bold uppercase tracking-[0.12em] text-slate-500">
                            Activity stream
                        </p>
                        <p className="text-[11px] font-medium text-slate-400">อัปเดตล่าสุดจากมือถือ</p>
                    </div>
                </div>
                <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[10px] font-bold tabular-nums text-slate-500">
                    {activities.length}
                </span>
            </div>

            <ul className={`relative px-3 py-3 ${compact ? 'max-h-32' : 'max-h-44'} overflow-y-auto`}>
                {activities.map((item, idx) => {
                    const meta = kindMeta[item.kind];
                    const Icon = meta.icon;
                    const isLast = idx === activities.length - 1;

                    return (
                        <li key={item.id} className="relative flex gap-3 pb-3 last:pb-0 animate-fade-in">
                            {!isLast && (
                                <span
                                    className={`absolute left-[11px] top-6 bottom-0 w-px bg-gradient-to-b ${meta.line} to-transparent`}
                                />
                            )}
                            <span
                                className={`relative z-[1] mt-0.5 flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-full ring-4 ${meta.dot}`}
                            >
                                <Icon size={11} className="text-white" strokeWidth={2.5} />
                            </span>
                            <div className={`min-w-0 flex-1 rounded-xl border border-white/60 px-3 py-2 ${meta.bg}`}>
                                <p className={`text-xs font-semibold leading-snug ${meta.text}`}>{item.message}</p>
                                <p className="mt-1 text-[10px] font-mono tabular-nums text-slate-400">
                                    {formatActivityTime(item.at)}
                                </p>
                            </div>
                        </li>
                    );
                })}
            </ul>
        </div>
    );
};

export default CountRecordActivityFeed;
