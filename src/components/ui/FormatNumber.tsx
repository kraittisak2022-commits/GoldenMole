import { formatDisplayNumber } from '../../utils';

const FormatNumber = ({ value, prefix = '฿', suffix = '' }: { value: number, prefix?: string; suffix?: string }) => {
    const full = formatDisplayNumber(value);

    return (
        <span title={`${prefix}${full}${suffix}`} className="cursor-help transition-opacity hover:opacity-80">
            {prefix}{full}{suffix}
        </span>
    );
};

export default FormatNumber;
