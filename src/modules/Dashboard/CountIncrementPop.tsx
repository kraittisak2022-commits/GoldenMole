import { useEffect, useState } from 'react';

interface CountIncrementPopProps {
    delta: number;
    color?: string;
    decrementColor?: string;
    className?: string;
}

/** Floating +/-N animation when count changes in real-time */
const CountIncrementPop = ({
    delta,
    color = '#10b981',
    decrementColor = '#fca5a5',
    className = '',
}: CountIncrementPopProps) => {
    const [visible, setVisible] = useState(true);

    useEffect(() => {
        setVisible(true);
        const timer = window.setTimeout(() => setVisible(false), 900);
        return () => window.clearTimeout(timer);
    }, [delta]);

    if (!visible || delta === 0) return null;

    const isUp = delta > 0;
    const display = isUp ? `+${delta}` : `${delta}`;
    const popClass = isUp ? 'count-increment-pop' : 'count-decrement-pop';

    return (
        <span
            className={`${popClass} pointer-events-none absolute left-1/2 top-0 z-20 -translate-x-1/2 font-black tabular-nums ${className}`}
            style={{ color: isUp ? color : decrementColor }}
            aria-hidden
        >
            {display}
        </span>
    );
};

export default CountIncrementPop;
