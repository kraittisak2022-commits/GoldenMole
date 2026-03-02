export const getToday = () => new Date().toISOString().split('T')[0];

export const getFirstDayOfMonth = () => {
    const d = new Date();
    d.setDate(1);
    return d.toISOString().split('T')[0];
};

export const getLastDayOfMonth = () => {
    const d = new Date();
    d.setMonth(d.getMonth() + 1);
    d.setDate(0);
    return d.toISOString().split('T')[0];
};

export const FormatNumber = ({ value, prefix = '฿' }: { value: number, prefix?: string }) => {
    // Note: This was a component in the original code, but as a util efficiently it should return string, 
    // but for the UI consistency I will keep it as a component-like helper or just use string formatting here and Text Component in UI.
    // However, the original code used it as a Component with a tooltip. I will move the Component to `components/ui/FormatNumber.tsx` but keep logic here? 
    // No, simpler to just keep utilities as pure JS functions.
    return value.toLocaleString();
};

export const formatNumberShort = (value: number) => {
    let short = value.toLocaleString();
    if (value >= 1000000) short = (value / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
    else if (value >= 100000) short = (value / 1000).toFixed(0) + 'K';
    return short;
}
