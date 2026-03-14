const TZ_TH = 'Asia/Bangkok';

/** วันที่ปัจจุบันในประเทศไทย (YYYY-MM-DD) */
export const getToday = () => new Date().toLocaleDateString('en-CA', { timeZone: TZ_TH });

/** ทำให้วันที่เป็นรูปแบบ YYYY-MM-DD เสมอ (รองรับทั้ง ISO string จาก DB) */
export const normalizeDate = (d: string | undefined): string => (d && d.length >= 10 ? d.slice(0, 10) : d || '');

export const getFirstDayOfMonth = () => {
    const d = new Date();
    return new Date(d.getFullYear(), d.getMonth(), 1).toLocaleDateString('en-CA', { timeZone: TZ_TH });
};

export const getLastDayOfMonth = () => {
    const d = new Date();
    return new Date(d.getFullYear(), d.getMonth() + 1, 0).toLocaleDateString('en-CA', { timeZone: TZ_TH });
};

/** เวลาปัจจุบันในประเทศไทย รูปแบบ 24 ชม. (HH:mm) */
export const getCurrentTimeTH = () => new Date().toLocaleTimeString('th-TH', { timeZone: TZ_TH, hour: '2-digit', minute: '2-digit', hour12: false });

/** วันที่+เวลา สำหรับประเทศไทย รูปแบบ 24 ชม. */
export const formatDateTimeTH = (date?: Date | string) => {
    const d = date ? new Date(date) : new Date();
    return d.toLocaleString('th-TH', { timeZone: TZ_TH, hour12: false });
};

export const formatDateBE = (dateString?: string) => {
    if (!dateString) return '-';
    const [year, month, day] = dateString.split('-');
    if (!year || !month || !day) return dateString;
    const beYear = parseInt(year) + 543;
    return `${day}/${month}/${beYear}`;
};

export const FormatNumber = ({ value }: { value: number }) => {
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
