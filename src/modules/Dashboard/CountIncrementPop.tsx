import { useEffect, useState } from 'react';

interface CountIncrementPopProps {
    delta: number;
    color?: string;
    className?: string;
}

/** Floating +N animation when count increases in real-time */
const CountIncrementPop = ({ delta, color = '#10b981', className = '' }: CountIncrementPopProps) => {
    const [visible, setVisible] = useState(true);

    useEffect(() => {
        setVisible(true);
        const timer = window.setTimeout(() => setVisible(false), 900);
        return () => window.clearTimeout(timer);
    }, [delta]);

    if (!visible || delta <= 0) return null;

    return (
        <span
            className={`count-increment-pop pointer-events-none absolute left-1/2 top-0 z-20 -translate-x-1/2 font-black tabular-nums ${className}`}
            style={{ color }}
            aria-hidden
        >
            +{delta}
        </span>
    );
};

export default CountIncrementPop;
