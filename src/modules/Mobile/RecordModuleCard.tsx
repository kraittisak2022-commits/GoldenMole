import { useState } from 'react';
import type { LucideIcon } from 'lucide-react';
import type { DailyModuleFillStatus } from './dailyModuleTransactions';

function iconTint(accent: string): string {
    const hex = accent.replace('#', '');
    if (hex.length !== 6) return '#334155';
    const r = parseInt(hex.slice(0, 2), 16);
    const g = parseInt(hex.slice(2, 4), 16);
    const b = parseInt(hex.slice(4, 6), 16);
    const mix = (c: number) => Math.round(c * 0.72 + 51 * 0.28);
    return `rgb(${mix(r)}, ${mix(g)}, ${mix(b)})`;
}

type RecordModuleCardProps = {
    title: string;
    icon: LucideIcon;
    fillStatus: DailyModuleFillStatus;
    tileColor: string;
    onTap: () => void;
    completeStatusLabelOverride?: string;
    statusMaxLines?: number;
};

const RecordModuleCard = ({
    title,
    icon: Icon,
    fillStatus,
    tileColor,
    onTap,
    completeStatusLabelOverride,
    statusMaxLines = 2,
}: RecordModuleCardProps) => {
    const [pressed, setPressed] = useState(false);
    const recorded = fillStatus === 'complete';
    const partial = fillStatus === 'incomplete';
    const detail = completeStatusLabelOverride?.trim();
    const hasDetail = Boolean(detail && detail.length > 0);
    const statusLabel =
        fillStatus === 'pending'
            ? 'แตะเพื่อบันทึก'
            : hasDetail
              ? detail!
              : recorded
                ? 'ครบแล้ว'
                : partial
                  ? 'ยังไม่ครบ'
                  : 'แตะเพื่อบันทึก';
    const statusColor = recorded ? '#15803D' : partial ? '#B45309' : '#94A3B8';
    const borderColor = recorded ? '#BBF7D0' : partial ? '#FDE68A' : '#E8EDF3';
    const dotColor = recorded ? '#22C55E' : partial ? '#F59E0B' : '#CBD5E1';

    return (
        <button
            type="button"
            onClick={onTap}
            onPointerDown={() => setPressed(true)}
            onPointerUp={() => setPressed(false)}
            onPointerLeave={() => setPressed(false)}
            onPointerCancel={() => setPressed(false)}
            className={`relative flex aspect-square w-full min-h-[96px] max-h-[200px] flex-col items-center justify-center rounded-[14px] border bg-white p-2 text-center touch-manipulation transition-transform duration-100 motion-reduce:transition-none ${
                pressed ? 'scale-[0.97]' : 'scale-100'
            }`}
            style={{
                borderColor,
                boxShadow: pressed ? 'none' : '0 2px 8px rgba(15, 23, 42, 0.04)',
            }}
        >
            <span
                className="absolute right-1.5 top-1.5 h-2 w-2 rounded-full"
                style={{ backgroundColor: dotColor }}
                aria-hidden
            />
            <Icon size={40} strokeWidth={1.75} style={{ color: iconTint(tileColor) }} className="shrink-0" />
            <p className="mt-1 line-clamp-3 w-full px-0.5 text-[11.5px] font-semibold leading-tight text-slate-800 sm:text-xs">
                {title}
            </p>
            <p
                className="mt-0.5 w-full px-0.5 text-[10px] font-medium leading-snug"
                style={{
                    color: statusColor,
                    display: '-webkit-box',
                    WebkitLineClamp: statusMaxLines,
                    WebkitBoxOrient: 'vertical',
                    overflow: 'hidden',
                }}
            >
                {statusLabel}
            </p>
        </button>
    );
};

export default RecordModuleCard;
