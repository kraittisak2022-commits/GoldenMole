import { useEffect, useRef, useState } from 'react';
import { Droplets, Truck } from 'lucide-react';
import type { CountRecordIncrement } from './countRecordUtils';

interface LiveIncrementOverlayProps {
    increments: CountRecordIncrement[];
}

interface FloatingPop {
    key: string;
    delta: number;
    kind: 'trip' | 'sand';
    slot: number;
}

const POP_DURATION_MS = 1800;
const HORIZONTAL_SLOTS = [18, 42, 66, 30, 54];

const LiveIncrementOverlay = ({ increments }: LiveIncrementOverlayProps) => {
    const [active, setActive] = useState<FloatingPop[]>([]);
    const seenIdsRef = useRef<Set<string>>(new Set());
    const slotRef = useRef(0);

    useEffect(() => {
        const newPops: FloatingPop[] = [];
        for (const inc of increments) {
            if (inc.delta <= 0 || seenIdsRef.current.has(inc.id)) continue;
            seenIdsRef.current.add(inc.id);
            const slot = HORIZONTAL_SLOTS[slotRef.current % HORIZONTAL_SLOTS.length]!;
            slotRef.current += 1;
            newPops.push({
                key: inc.id,
                delta: inc.delta,
                kind: inc.kind,
                slot,
            });
        }
        if (newPops.length === 0) return;

        setActive((prev) => [...prev, ...newPops]);
        const timers = newPops.map((pop) =>
            window.setTimeout(() => {
                setActive((prev) => prev.filter((p) => p.key !== pop.key));
            }, POP_DURATION_MS),
        );
        return () => timers.forEach((t) => window.clearTimeout(t));
    }, [increments]);

    if (active.length === 0) return null;

    return (
        <div className="pointer-events-none absolute inset-0 z-30 overflow-hidden" aria-hidden>
            {active.map((pop) => {
                const Icon = pop.kind === 'trip' ? Truck : Droplets;
                const glow =
                    pop.kind === 'trip'
                        ? '0 0 24px rgba(96,165,250,0.9), 0 0 48px rgba(59,130,246,0.5)'
                        : '0 0 24px rgba(244,114,182,0.9), 0 0 48px rgba(219,39,119,0.5)';
                const color = pop.kind === 'trip' ? '#fef08a' : '#fce7f3';

                return (
                    <div
                        key={pop.key}
                        className="score-pop-float absolute bottom-[28%] flex flex-col items-center"
                        style={{ left: `${pop.slot}%` }}
                    >
                        <div
                            className="score-pop-in flex items-center gap-2 rounded-2xl border border-white/25 bg-slate-900/75 px-4 py-2 backdrop-blur-md"
                            style={{ boxShadow: glow }}
                        >
                            <Icon size={22} style={{ color }} strokeWidth={2.5} />
                            <span
                                className="text-3xl font-black tabular-nums leading-none tracking-tight"
                                style={{ color, textShadow: glow }}
                            >
                                +{pop.delta}
                            </span>
                        </div>
                    </div>
                );
            })}
        </div>
    );
};

export default LiveIncrementOverlay;
