import { formatNumberShort } from '../../utils';

const FormatNumber = ({ value, prefix = '฿', suffix = '' }: { value: number, prefix?: string; suffix?: string }) => {
    const full = value.toLocaleString();
    const short = formatNumberShort(value);

    return (
        <span title={`${prefix}${full}${suffix}`} className="cursor-help transition-opacity hover:opacity-80">
            {prefix}{short}{suffix}
        </span>
    );
};

export default FormatNumber;
