import { formatNumberShort } from '../../utils';

const FormatNumber = ({ value, prefix = '฿' }: { value: number, prefix?: string }) => {
    const full = value.toLocaleString();
    const short = formatNumberShort(value);

    return (
        <span title={`${prefix}${full}`} className="cursor-help transition-opacity hover:opacity-80">
            {prefix}{short}
        </span>
    );
};

export default FormatNumber;
