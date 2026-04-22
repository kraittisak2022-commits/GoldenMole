import { formatDisplayNumber } from '../../utils';

const formatCompactNumber = (value: number) => {
    const abs = Math.abs(value);
    const sign = value < 0 ? '-' : '';
    if (abs >= 1000000) return `${sign}${(abs / 1000000).toFixed(1).replace(/\.0$/, '')}m`;
    if (abs >= 1000) return `${sign}${(abs / 1000).toFixed(1).replace(/\.0$/, '')}k`;
    return `${sign}${formatDisplayNumber(abs)}`;
};

const FormatNumber = ({ value, prefix = '฿', suffix = '' }: { value: number, prefix?: string; suffix?: string }) => {
    const full = formatDisplayNumber(value);
    const compact = formatCompactNumber(value);

    return (
        <span title={`${prefix}${full}${suffix}`} className="cursor-help transition-opacity hover:opacity-80">
            {prefix}{compact}{suffix}
        </span>
    );
};

export default FormatNumber;
