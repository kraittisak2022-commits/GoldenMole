import { Activity } from 'lucide-react';
import type { CountRecordActivity } from './countRecordUtils';

interface CountRecordActivityFeedProps {
    activities: CountRecordActivity[];
    compact?: boolean;
}

const kindStyle: Record<CountRecordActivity['kind'], string> = {
    trip: 'border-blue-200 bg-blue-50/80 text-blue-900',
    sand: 'border-pink-200 bg-pink-50/80 text-pink-900',
    delete: 'border-rose-200 bg-rose-50/80 text-rose-900',
};

const CountRecordActivityFeed = ({ activities, compact = false }: CountRecordActivityFeedProps) => {
    if (activities.length === 0) return null;

    return (
        <div
            className={`rounded-xl border border-slate-200 bg-white overflow-hidden ${
                compact ? '' : 'shadow-sm'
            }`}
        >
            <div className="px-3 py-2 border-b border-slate-100 flex items-center gap-2 bg-slate-50/80">
                <Activity size={14} className="text-indigo-500" />
                <span className="text-xs font-extrabold text-slate-600 uppercase tracking-wide">
                    อัปเดตล่าสุดแบบ Real-time
                </span>
            </div>
            <ul className={`divide-y divide-slate-100 ${compact ? 'max-h-28' : 'max-h-40'} overflow-y-auto`}>
                {activities.map((item) => (
                    <li
                        key={item.id}
                        className={`px-3 py-2 text-xs font-semibold animate-fade-in border-l-2 ${kindStyle[item.kind]}`}
                    >
                        {item.message}
                    </li>
                ))}
            </ul>
        </div>
    );
};

export default CountRecordActivityFeed;
