import { useMemo, useState, useCallback } from 'react';
import { AlertTriangle, CalendarRange, ClipboardCheck, Trash2, ChevronLeft, ChevronRight, FileDown, Printer } from 'lucide-react';
import type { AppSettings, Transaction, AdminUser } from '../../types';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import { getToday, normalizeDate, formatDateBE, formatDateTimeTH, getThaiPublicHolidayMap } from '../../utils';

const TZ_TH = 'Asia/Bangkok';

const addOneDayTH = (ymd: string): string => {
    const d = new Date(`${ymd}T12:00:00`);
    d.setDate(d.getDate() + 1);
    return d.toLocaleDateString('en-CA', { timeZone: TZ_TH });
};

/** วันแรก–วันสุดท้ายของเดือนปฏิทิน (เดือน 1–12 จากสตริง YYYY-MM-DD) */
const getMonthBoundsFromYmd = (ymd: string): { start: string; end: string } => {
    const n = normalizeDate(ymd);
    const [y, m] = n.split('-').map(Number);
    const lastDay = new Date(y, m, 0).getDate();
    const pad = (v: number) => String(v).padStart(2, '0');
    return { start: `${y}-${pad(m)}-01`, end: `${y}-${pad(m)}-${pad(lastDay)}` };
};

const shiftMonthBy = (startYmd: string, deltaMonth: number): { start: string; end: string } => {
    const n = normalizeDate(startYmd);
    const [y, m] = n.split('-').map(Number);
    const d = new Date(y, m - 1 + deltaMonth, 1);
    const ny = d.getFullYear();
    const nm = d.getMonth() + 1;
    return getMonthBoundsFromYmd(`${ny}-${String(nm).padStart(2, '0')}-15`);
};

const enumerateDates = (start: string, end: string): string[] => {
    const a = normalizeDate(start);
    const b = normalizeDate(end);
    if (!a || !b || a > b) return [];
    const out: string[] = [];
    let cur = a;
    while (cur <= b) {
        out.push(cur);
        cur = addOneDayTH(cur);
    }
    return out;
};

const CALENDAR_WEEKDAY_TH = ['อา.', 'จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.'];
type ReportStatus = 'new' | 'investigating' | 'resolved' | 'closed';
type DayFilterMode = 'all' | 'empty' | 'duplicate';
const REPORT_STATUS_LABEL: Record<ReportStatus, string> = {
    new: 'ใหม่',
    investigating: 'กำลังตรวจ',
    resolved: 'แก้แล้ว',
    closed: 'ปิดเคส',
};

const getWizardStepFilled = (date: string, txs: Transaction[]): Record<number, boolean> => {
    const norm = normalizeDate(date);
    const day = txs.filter(t => normalizeDate(t.date) === norm);
    return {
        1: day.some(t => t.category === 'Labor'),
        2: day.some(t => t.category === 'Vehicle'),
        3: day.some(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip'),
        4: day.some(t => t.category === 'DailyLog' && t.subCategory === 'Sand'),
        5: day.some(t => t.category === 'Fuel'),
        6: day.some(t => t.category === 'Income' && t.type === 'Income'),
        7: day.some(t => t.category === 'DailyLog' && t.subCategory === 'Event'),
    };
};

const isSunday = (ymd: string) => {
    const d = new Date(`${ymd}T12:00:00`);
    return d.getDay() === 0;
};

const dupKey = (t: Transaction) => {
    const d = normalizeDate(t.date);
    const desc = (t.description || '').trim();
    const sub = t.subCategory || '';
    return `${d}|${t.category}|${sub}|${t.amount}|${desc}`;
};

const normalizeText = (value: string) => String(value || '').toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, ' ').replace(/\s+/g, ' ').trim();
const tokenSet = (value: string) => new Set(normalizeText(value).split(' ').filter(Boolean));
const textSimilarity = (a: string, b: string) => {
    const sa = tokenSet(a);
    const sb = tokenSet(b);
    if (sa.size === 0 && sb.size === 0) return 1;
    if (sa.size === 0 || sb.size === 0) return 0;
    let inter = 0;
    for (const t of sa) if (sb.has(t)) inter += 1;
    const union = new Set([...sa, ...sb]).size;
    return union === 0 ? 0 : inter / union;
};
const extractTimeMinutes = (t: Transaction): number | null => {
    const candidates = [t.eventTime, t.workDetails, t.description].map(v => String(v || '')).filter(Boolean);
    for (const c of candidates) {
        const m = c.match(/\b([01]?\d|2[0-3]):([0-5]\d)\b/);
        if (!m) continue;
        return Number(m[1]) * 60 + Number(m[2]);
    }
    return null;
};
const getStepByCategory = (category?: string, subCategory?: string) => {
    if (category === 'Labor') return 1;
    if (category === 'Vehicle') return 2;
    if (category === 'Fuel') return 5;
    if (category === 'Income') return 6;
    if (category === 'DailyLog' && subCategory === 'VehicleTrip') return 3;
    if (category === 'DailyLog' && subCategory === 'Sand') return 4;
    if (category === 'DailyLog' && subCategory === 'Event') return 7;
    return 0;
};
const getMonthLabelFromYmd = (ymd: string) =>
    new Date(`${normalizeDate(ymd)}T12:00:00`).toLocaleDateString('th-TH', { month: 'short', year: '2-digit', timeZone: TZ_TH });

interface DataVerificationModuleProps {
    /** โหมดเมนู “ตรวจสอบภาพรวม (1 เดือน)” — ค่าเริ่มต้นเป็นวันแรก–สุดท้ายของเดือนปัจจุบัน */
    monthOverviewMode?: boolean;
    transactions: Transaction[];
    settings: AppSettings;
    setSettings: (updater: AppSettings | ((prev: AppSettings) => AppSettings)) => void;
    currentAdmin: AdminUser | null;
    addLog?: (action: string, details: string) => void;
    onGoToDailyWizard?: (date?: string, step?: number) => void;
}

const defaultRange = (monthMode: boolean | undefined) => {
    const today = getToday();
    if (monthMode) return getMonthBoundsFromYmd(today);
    const d = new Date(`${today}T12:00:00`);
    d.setDate(d.getDate() - 44);
    return { start: d.toLocaleDateString('en-CA', { timeZone: TZ_TH }), end: today };
};

const DataVerificationModule = ({
    monthOverviewMode,
    transactions,
    settings,
    setSettings,
    currentAdmin,
    addLog,
    onGoToDailyWizard,
}: DataVerificationModuleProps) => {
    const today = getToday();
    const init = defaultRange(monthOverviewMode);
    const [rangeEnd, setRangeEnd] = useState(init.end);
    const [rangeStart, setRangeStart] = useState(init.start);
    const [hideSunday, setHideSunday] = useState(false);
    const [hidePublicHoliday, setHidePublicHoliday] = useState(false);
    const [dayFilterMode, setDayFilterMode] = useState<DayFilterMode>('all');
    const [emptyWeight, setEmptyWeight] = useState(4);
    const [duplicateWeight, setDuplicateWeight] = useState(2);
    const [reportDate, setReportDate] = useState(today);
    const [reportBody, setReportBody] = useState('');
    const [statusNote, setStatusNote] = useState('');

    const reports = settings.appDefaults?.dataQualityReports || [];
    const auditTrail = settings.appDefaults?.dataQualityAuditTrail || [];
    const thresholds = settings.appDefaults?.dataQualityThresholds || {};
    const incomeZeroThreshold = Math.max(0, Number(thresholds.incomeZeroThreshold ?? 0));
    const laborHighAmountThreshold = Math.max(0, Number(thresholds.laborHighAmountThreshold ?? 25000));
    const fuelHighLitersThreshold = Math.max(0, Number(thresholds.fuelHighLitersThreshold ?? 400));
    const holidayMapByYear = useMemo(() => {
        const years = new Set<number>();
        for (const d of enumerateDates(rangeStart, rangeEnd)) years.add(Number(d.slice(0, 4)));
        return Object.fromEntries(Array.from(years).map(y => [String(y), getThaiPublicHolidayMap(y)]));
    }, [rangeStart, rangeEnd]);
    const isThaiHoliday = useCallback((ymd: string) => {
        const year = ymd.slice(0, 4);
        return Boolean(holidayMapByYear[year]?.[ymd]);
    }, [holidayMapByYear]);

    const datesInRange = useMemo(() => {
        const raw = enumerateDates(rangeStart, rangeEnd);
        return raw.filter(d => {
            if (hideSunday && isSunday(d)) return false;
            if (hidePublicHoliday && isThaiHoliday(d)) return false;
            return true;
        });
    }, [rangeStart, rangeEnd, hideSunday, hidePublicHoliday, isThaiHoliday]);

    const dayAnalysis = useMemo(() => {
        const emptyDays: string[] = [];

        for (const d of datesInRange) {
            const filled = getWizardStepFilled(d, transactions);
            const done = Object.values(filled).filter(Boolean).length;
            if (done === 0) {
                emptyDays.push(d);
            }
        }
        return { emptyDays };
    }, [datesInRange, transactions]);

    const fullDaysCount = useMemo(() => {
        let n = 0;
        for (const d of datesInRange) {
            const filled = getWizardStepFilled(d, transactions);
            if (Object.values(filled).every(Boolean)) n += 1;
        }
        return n;
    }, [datesInRange, transactions]);

    const exactDuplicateClusters = useMemo(() => {
        const skip = new Set(['Payroll', 'PayrollUnlock']);
        const rs = normalizeDate(rangeStart);
        const re = normalizeDate(rangeEnd);
        const map = new Map<string, Transaction[]>();
        for (const t of transactions) {
            if (skip.has(t.category)) continue;
            const td = normalizeDate(t.date);
            if (td < rs || td > re) continue;
            const k = dupKey(t);
            const arr = map.get(k) || [];
            arr.push(t);
            map.set(k, arr);
        }
        const clusters: { key: string; items: Transaction[] }[] = [];
        for (const [, items] of map) {
            if (items.length >= 2) clusters.push({ key: `${dupKey(items[0])}|${items.map(i => i.id).join(',')}`, items });
        }
        clusters.sort((a, b) => normalizeDate(b.items[0].date).localeCompare(normalizeDate(a.items[0].date)));
        return clusters;
    }, [transactions, rangeStart, rangeEnd]);
    const nearDuplicateFindings = useMemo(() => {
        const skip = new Set(['Payroll', 'PayrollUnlock']);
        const rs = normalizeDate(rangeStart);
        const re = normalizeDate(rangeEnd);
        const bucket = new Map<string, Transaction[]>();
        for (const t of transactions) {
            if (skip.has(t.category)) continue;
            const td = normalizeDate(t.date);
            if (td < rs || td > re) continue;
            const key = `${td}|${t.category}|${t.subCategory || ''}`;
            const arr = bucket.get(key) || [];
            arr.push(t);
            bucket.set(key, arr);
        }
        const findings: Array<{ id: string; date: string; category: string; subCategory?: string; amountA: number; amountB: number; descA: string; descB: string; reason: string }> = [];
        for (const [, items] of bucket) {
            if (items.length < 2) continue;
            for (let i = 0; i < items.length; i += 1) {
                for (let j = i + 1; j < items.length; j += 1) {
                    const a = items[i];
                    const b = items[j];
                    const amountA = Number(a.amount || 0);
                    const amountB = Number(b.amount || 0);
                    const amountDiff = Math.abs(amountA - amountB);
                    const amountTol = Math.max(30, Math.min(Math.abs(amountA), Math.abs(amountB)) * 0.05);
                    const sim = textSimilarity(a.description || '', b.description || '');
                    const ta = extractTimeMinutes(a);
                    const tb = extractTimeMinutes(b);
                    const nearTime = ta != null && tb != null ? Math.abs(ta - tb) <= 20 : false;
                    const likely = (amountDiff <= amountTol && sim >= 0.45) || sim >= 0.88 || (nearTime && amountDiff <= Math.max(100, amountTol));
                    if (!likely) continue;
                    findings.push({
                        id: `${a.id}_${b.id}`,
                        date: normalizeDate(a.date),
                        category: a.category,
                        subCategory: a.subCategory,
                        amountA,
                        amountB,
                        descA: a.description || '',
                        descB: b.description || '',
                        reason: sim >= 0.88 ? 'รายละเอียดใกล้เคียงมาก' : nearTime ? 'เวลาใกล้กันผิดปกติ' : 'จำนวนเงินและรายละเอียดใกล้เคียง',
                    });
                }
            }
        }
        findings.sort((a, b) => b.date.localeCompare(a.date));
        return findings.slice(0, 200);
    }, [transactions, rangeStart, rangeEnd]);
    const duplicateDaySet = useMemo(() => {
        const s = new Set<string>();
        exactDuplicateClusters.forEach(c => s.add(normalizeDate(c.items[0].date)));
        nearDuplicateFindings.forEach(f => s.add(f.date));
        return s;
    }, [exactDuplicateClusters, nearDuplicateFindings]);
    const duplicateClusterCount = exactDuplicateClusters.length + nearDuplicateFindings.length;
    const qualityScore = useMemo(() => {
        const deduction = dayAnalysis.emptyDays.length * Math.max(0, emptyWeight) + duplicateClusterCount * Math.max(0, duplicateWeight);
        return Math.max(0, 100 - deduction);
    }, [dayAnalysis.emptyDays.length, duplicateClusterCount, emptyWeight, duplicateWeight]);
    const ruleFindings = useMemo(() => {
        const out: Array<{ id: string; date: string; rule: string; detail: string; severity: 'medium' | 'high' }> = [];
        for (const d of datesInRange) {
            const dayTx = transactions.filter(t => normalizeDate(t.date) === d);
            if (dayTx.length === 0) continue;
            const incomeAmount = dayTx.filter(t => t.category === 'Income' && t.type === 'Income').reduce((s, t) => s + Number(t.amount || 0), 0);
            const laborAmount = dayTx.filter(t => t.category === 'Labor').reduce((s, t) => s + Number(t.amount || 0), 0);
            const fuelLiters = dayTx.filter(t => t.category === 'Fuel').reduce((s, t) => s + (Number(t.quantity || 0) || 0), 0);
            const tripCount = dayTx.filter(t => (t.category === 'DailyLog' && t.subCategory === 'VehicleTrip') || t.category === 'Vehicle').length;
            if (incomeAmount <= incomeZeroThreshold && dayTx.some(t => t.category === 'Income')) {
                out.push({ id: `rule_income_${d}`, date: d, rule: 'รายรับเป็น 0', detail: `รายรับรวม ${incomeAmount.toLocaleString()} บาท <= threshold ${incomeZeroThreshold.toLocaleString()}`, severity: 'medium' });
            }
            if (laborAmount >= laborHighAmountThreshold) {
                out.push({ id: `rule_labor_${d}`, date: d, rule: 'ค่าแรงสูงผิดปกติ', detail: `ค่าแรง ${laborAmount.toLocaleString()} บาท >= threshold ${laborHighAmountThreshold.toLocaleString()}`, severity: 'high' });
            }
            if (fuelLiters >= fuelHighLitersThreshold && tripCount === 0) {
                out.push({ id: `rule_fuel_${d}`, date: d, rule: 'น้ำมันมากแต่ไม่มีเที่ยวรถ', detail: `น้ำมัน ${fuelLiters.toLocaleString()} ลิตร >= threshold ${fuelHighLitersThreshold.toLocaleString()} แต่ไม่มีเที่ยวรถ`, severity: 'high' });
            }
        }
        out.sort((a, b) => b.date.localeCompare(a.date));
        return out;
    }, [datesInRange, transactions, incomeZeroThreshold, laborHighAmountThreshold, fuelHighLitersThreshold]);
    const trend3Months = useMemo(() => {
        const rows: Array<{ key: string; label: string; score: number; emptyDays: number; duplicates: number; cases: number }> = [];
        for (let back = 2; back >= 0; back -= 1) {
            const m = shiftMonthBy(rangeStart, -back);
            const monthDates = enumerateDates(m.start, m.end).filter(d => {
                if (hideSunday && isSunday(d)) return false;
                if (hidePublicHoliday && isThaiHoliday(d)) return false;
                return true;
            });
            const emptyDays = monthDates.filter(d => {
                const filled = getWizardStepFilled(d, transactions);
                return Object.values(filled).every(v => !v);
            }).length;
            const txMonth = transactions.filter(t => {
                const td = normalizeDate(t.date);
                return td >= m.start && td <= m.end;
            });
            const duplicateMap = new Map<string, number>();
            txMonth.forEach(t => {
                const k = dupKey(t);
                duplicateMap.set(k, (duplicateMap.get(k) || 0) + 1);
            });
            let duplicates = 0;
            for (const [, n] of duplicateMap) if (n >= 2) duplicates += 1;
            const cases = reports.filter(r => {
                const d = normalizeDate(r.targetDate);
                return d >= m.start && d <= m.end;
            }).length;
            const score = Math.max(0, 100 - (emptyDays * Math.max(0, emptyWeight)) - (duplicates * Math.max(0, duplicateWeight)));
            rows.push({ key: m.start, label: getMonthLabelFromYmd(m.start), score, emptyDays, duplicates, cases });
        }
        return rows;
    }, [rangeStart, hideSunday, hidePublicHoliday, isThaiHoliday, transactions, reports, emptyWeight, duplicateWeight]);

    const monthLabelTH = useMemo(
        () =>
            new Date(`${normalizeDate(rangeStart)}T12:00:00`).toLocaleDateString('th-TH', {
                month: 'long',
                year: 'numeric',
                timeZone: TZ_TH,
            }),
        [rangeStart],
    );
    const calendarCells = useMemo(() => {
        const monthBounds = getMonthBoundsFromYmd(rangeStart);
        const monthDates = enumerateDates(monthBounds.start, monthBounds.end);
        const emptySet = new Set(dayAnalysis.emptyDays);
        const rangeSet = new Set(datesInRange);
        const firstWeekday = new Date(`${monthBounds.start}T12:00:00`).getDay();
        const cells: Array<{ date: string; day: number; inRange: boolean; empty: boolean; duplicate: boolean; isSunday: boolean; isHoliday: boolean } | null> = [];
        for (let i = 0; i < firstWeekday; i += 1) cells.push(null);
        for (const d of monthDates) {
            const day = Number(d.slice(8, 10));
            cells.push({
                date: d,
                day,
                inRange: rangeSet.has(d),
                empty: emptySet.has(d),
                duplicate: duplicateDaySet.has(d),
                isSunday: isSunday(d),
                isHoliday: isThaiHoliday(d),
            });
        }
        while (cells.length % 7 !== 0) cells.push(null);
        return cells;
    }, [rangeStart, datesInRange, dayAnalysis.emptyDays, duplicateDaySet, isThaiHoliday]);

    const submitReport = useCallback(() => {
        const body = reportBody.trim();
        const td = normalizeDate(reportDate);
        if (!body || !td) return;
        const id = `${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
        const entry = {
            id,
            targetDate: td,
            body,
            status: 'new' as ReportStatus,
            createdAt: formatDateTimeTH(),
            updatedAt: formatDateTimeTH(),
            adminId: currentAdmin?.id,
            adminName: currentAdmin?.displayName || currentAdmin?.username,
        };
        setSettings(prev => ({
            ...prev,
            appDefaults: {
                ...(prev.appDefaults || {}),
                dataQualityReports: [entry, ...(prev.appDefaults?.dataQualityReports || [])].slice(0, 200),
            },
        }));
        addLog?.(
            'data_quality_report',
            `แจ้งตรวจสอบข้อมูล วันที่ ${formatDateBE(td)} | ${body.slice(0, 500)}`,
        );
        setReportBody('');
    }, [reportBody, reportDate, setSettings, currentAdmin, addLog]);
    const updateReportStatus = useCallback((id: string, status: ReportStatus, note?: string) => {
        setSettings(prev => ({
            ...prev,
            appDefaults: {
                ...(prev.appDefaults || {}),
                dataQualityReports: (prev.appDefaults?.dataQualityReports || []).map(r => r.id === id ? { ...r, status, updatedAt: formatDateTimeTH() } : r),
                dataQualityAuditTrail: (() => {
                    const target = (prev.appDefaults?.dataQualityReports || []).find(r => r.id === id);
                    if (!target) return prev.appDefaults?.dataQualityAuditTrail || [];
                    const fromStatus = (target.status || 'new') as ReportStatus;
                    if (fromStatus === status) return prev.appDefaults?.dataQualityAuditTrail || [];
                    const entry = {
                        id: `${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
                        reportId: id,
                        reportDate: target.targetDate,
                        action: 'status_change' as const,
                        fromStatus,
                        toStatus: status,
                        note: note?.trim() || undefined,
                        changedByAdminId: currentAdmin?.id,
                        changedByAdminName: currentAdmin?.displayName || currentAdmin?.username,
                        changedAt: formatDateTimeTH(),
                    };
                    return [entry, ...(prev.appDefaults?.dataQualityAuditTrail || [])].slice(0, 500);
                })(),
            },
        }));
    }, [setSettings, currentAdmin]);

    const removeReport = useCallback((id: string) => {
        setSettings(prev => ({
            ...prev,
            appDefaults: {
                ...(prev.appDefaults || {}),
                dataQualityReports: (prev.appDefaults?.dataQualityReports || []).filter(r => r.id !== id),
            },
        }));
    }, [setSettings]);

    const goThisMonth = () => {
        const b = getMonthBoundsFromYmd(today);
        setRangeStart(b.start);
        setRangeEnd(b.end);
    };
    const goPrevMonth = () => {
        const b = shiftMonthBy(rangeStart, -1);
        setRangeStart(b.start);
        setRangeEnd(b.end);
    };
    const goNextMonth = () => {
        const b = shiftMonthBy(rangeStart, 1);
        setRangeStart(b.start);
        setRangeEnd(b.end);
    };
    const exportCsv = () => {
        const rows: string[][] = [];
        rows.push(['ประเภท', 'ช่วงวันที่', 'ข้อมูล']);
        rows.push(['สรุป', `${rangeStart} - ${rangeEnd}`, `Score=${qualityScore}, EmptyDays=${dayAnalysis.emptyDays.length}, DuplicateGroups=${duplicateClusterCount}`]);
        dayAnalysis.emptyDays.forEach(d => rows.push(['วันไม่มีบันทึก', d, 'ไม่มีข้อมูล 7 ขั้นใน Daily Wizard']));
        exactDuplicateClusters.forEach(c => {
            const s = c.items[0];
            rows.push(['ซ้ำแบบตรง', normalizeDate(s.date), `${s.category}/${s.subCategory || '-'} amount=${s.amount} count=${c.items.length}`]);
        });
        nearDuplicateFindings.forEach(f => rows.push(['ซ้ำใกล้เคียง', f.date, `${f.category}/${f.subCategory || '-'} ${f.reason} amountA=${f.amountA} amountB=${f.amountB}`]));
        reports.forEach(r => rows.push(['เคสแจ้งเตือน', r.targetDate, `[${REPORT_STATUS_LABEL[(r.status || 'new') as ReportStatus]}] ${r.body}`]));
        const csv = rows.map(cols => cols.map(v => `"${String(v).replace(/"/g, '""')}"`).join(',')).join('\n');
        const blob = new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `data-quality-${rangeStart}-to-${rangeEnd}.csv`;
        a.click();
        URL.revokeObjectURL(url);
    };
    const printReport = () => {
        const html = `<!doctype html><html><head><meta charset="utf-8"/><title>Data Quality Report</title><style>body{font-family:Arial,sans-serif;padding:20px}h1{font-size:18px}table{width:100%;border-collapse:collapse;margin-top:10px}th,td{border:1px solid #ccc;padding:6px;font-size:12px;text-align:left}</style></head><body><h1>รายงานตรวจสอบข้อมูล ${monthLabelTH}</h1><p>ช่วง ${rangeStart} ถึง ${rangeEnd} | Score ${qualityScore}</p><table><thead><tr><th>หมวด</th><th>รายละเอียด</th></tr></thead><tbody><tr><td>วันไม่มีบันทึก</td><td>${dayAnalysis.emptyDays.map(d => formatDateBE(d)).join(', ') || '-'}</td></tr><tr><td>กลุ่มซ้ำแบบตรง</td><td>${exactDuplicateClusters.length}</td></tr><tr><td>กลุ่มซ้ำใกล้เคียง</td><td>${nearDuplicateFindings.length}</td></tr><tr><td>เคสแจ้งเตือน</td><td>${reports.length}</td></tr></tbody></table></body></html>`;
        const w = window.open('', '_blank');
        if (!w) return;
        w.document.open();
        w.document.write(html);
        w.document.close();
        w.focus();
        w.print();
    };

    return (
        <div className="space-y-6">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
                <div>
                    <h3 className="text-base font-bold text-slate-800 dark:text-slate-100 flex items-center gap-2">
                        <ClipboardCheck className="h-5 w-5 text-amber-600 dark:text-amber-400 shrink-0" />
                        {monthOverviewMode ? 'ตรวจสอบภาพรวมรายเดือน' : 'ระบบตรวจสอบข้อมูล (Daily Wizard)'}
                    </h3>
                    <p className="mt-1 text-sm text-slate-600 dark:text-slate-400 max-w-2xl">{monthOverviewMode ? `ดูภาพรวมว่าวันไหนไม่มีบันทึกหรือมีข้อมูลซ้ำ พร้อมติดตามสถานะการแก้ไขได้ในหน้าเดียว (${monthLabelTH})` : 'ตรวจว่าวันไหนยังไม่มีบันทึกงานประจำวัน และรายการที่น่าสงสัยว่าซ้ำกัน'}</p>
                </div>
                <div className="flex flex-wrap gap-2">
                    {onGoToDailyWizard && (
                        <Button type="button" variant="outline" className="shrink-0" onClick={() => onGoToDailyWizard()}>
                            ไปบันทึกงานประจำวัน
                        </Button>
                    )}
                    <Button type="button" variant="outline" className="px-3" onClick={exportCsv}><FileDown className="h-4 w-4" /> Export CSV</Button>
                    <Button type="button" variant="outline" className="px-3" onClick={printReport}><Printer className="h-4 w-4" /> พิมพ์/PDF</Button>
                </div>
            </div>

            <Card className="p-4 sm:p-5 border-indigo-200/60 dark:border-indigo-500/25">
                <h4 className="text-sm font-bold text-slate-800 dark:text-slate-100 mb-3">สรุปภาพรวมในช่วงที่เลือก</h4>
                <div className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-6">
                    <div className="rounded-xl bg-slate-50 dark:bg-white/[0.04] px-3 py-2.5">
                        <p className="text-[11px] font-medium text-slate-500 dark:text-slate-400">วันในช่วง</p>
                        <p className="text-xl font-bold text-slate-800 dark:text-slate-100">{datesInRange.length}</p>
                    </div>
                    <div className="rounded-xl bg-amber-50/90 dark:bg-amber-500/10 px-3 py-2.5">
                        <p className="text-[11px] font-medium text-amber-800/80 dark:text-amber-200/90">ไม่มีบันทึกเลย</p>
                        <p className="text-xl font-bold text-amber-900 dark:text-amber-100">{dayAnalysis.emptyDays.length}</p>
                    </div>
                    <div className="rounded-xl bg-orange-50/90 dark:bg-orange-500/10 px-3 py-2.5">
                        <p className="text-[11px] font-medium text-orange-800/80 dark:text-orange-200/90">กลุ่มซ้ำทั้งหมด</p>
                        <p className="text-xl font-bold text-orange-900 dark:text-orange-100">{duplicateClusterCount}</p>
                    </div>
                    <div className="rounded-xl bg-emerald-50/90 dark:bg-emerald-500/10 px-3 py-2.5 col-span-2 sm:col-span-1">
                        <p className="text-[11px] font-medium text-emerald-800/80 dark:text-emerald-200/90">วันที่ครบ 7 ขั้น</p>
                        <p className="text-xl font-bold text-emerald-900 dark:text-emerald-100">{fullDaysCount}</p>
                    </div>
                    <div className="rounded-xl bg-violet-50/90 dark:bg-violet-500/10 px-3 py-2.5 col-span-2">
                        <p className="text-[11px] font-medium text-violet-800/80 dark:text-violet-200/90">Data Quality Score</p>
                        <p className="text-xl font-bold text-violet-900 dark:text-violet-100">{qualityScore}</p>
                        <p className="text-[10px] text-violet-700/80 dark:text-violet-200/80 mt-0.5">100 - (วันว่าง*{emptyWeight}) - (ซ้ำ*{duplicateWeight})</p>
                    </div>
                </div>
                <div className="mt-3 flex flex-wrap items-center gap-2 text-xs">
                    <span className="text-slate-600 dark:text-slate-400">น้ำหนัก Score:</span>
                    <label className="flex items-center gap-1">วันว่าง <input type="number" min="0" max="20" value={emptyWeight} onChange={e => setEmptyWeight(Number(e.target.value || 0))} className="w-16 rounded border border-slate-200 dark:border-white/20 bg-white dark:bg-white/5 px-2 py-1" /></label>
                    <label className="flex items-center gap-1">ข้อมูลซ้ำ <input type="number" min="0" max="20" value={duplicateWeight} onChange={e => setDuplicateWeight(Number(e.target.value || 0))} className="w-16 rounded border border-slate-200 dark:border-white/20 bg-white dark:bg-white/5 px-2 py-1" /></label>
                </div>
                <div className="mt-3 grid gap-2 sm:grid-cols-3 text-xs">
                    <label className="flex items-center gap-1">Threshold รายรับเป็น 0 <input type="number" min="0" value={incomeZeroThreshold} onChange={e => setSettings(prev => ({ ...prev, appDefaults: { ...(prev.appDefaults || {}), dataQualityThresholds: { ...(prev.appDefaults?.dataQualityThresholds || {}), incomeZeroThreshold: Number(e.target.value || 0) } } }))} className="w-20 rounded border border-slate-200 dark:border-white/20 bg-white dark:bg-white/5 px-2 py-1" /></label>
                    <label className="flex items-center gap-1">Threshold ค่าแรงสูง <input type="number" min="0" value={laborHighAmountThreshold} onChange={e => setSettings(prev => ({ ...prev, appDefaults: { ...(prev.appDefaults || {}), dataQualityThresholds: { ...(prev.appDefaults?.dataQualityThresholds || {}), laborHighAmountThreshold: Number(e.target.value || 0) } } }))} className="w-24 rounded border border-slate-200 dark:border-white/20 bg-white dark:bg-white/5 px-2 py-1" /></label>
                    <label className="flex items-center gap-1">Threshold น้ำมันสูง (ลิตร) <input type="number" min="0" value={fuelHighLitersThreshold} onChange={e => setSettings(prev => ({ ...prev, appDefaults: { ...(prev.appDefaults || {}), dataQualityThresholds: { ...(prev.appDefaults?.dataQualityThresholds || {}), fuelHighLitersThreshold: Number(e.target.value || 0) } } }))} className="w-24 rounded border border-slate-200 dark:border-white/20 bg-white dark:bg-white/5 px-2 py-1" /></label>
                </div>
            </Card>

            <Card className="p-4 sm:p-5">
                <h4 className="font-bold text-slate-800 dark:text-slate-100 mb-2">Dashboard mini trend (3 เดือนล่าสุด)</h4>
                <div className="space-y-2">
                    {trend3Months.map(m => (
                        <div key={m.key} className="rounded-lg border border-slate-100 dark:border-white/10 bg-slate-50/70 dark:bg-white/[0.03] p-2.5">
                            <div className="flex items-center justify-between text-xs mb-1">
                                <span className="font-semibold text-slate-700 dark:text-slate-300">{m.label}</span>
                                <span className="text-slate-500">Score {m.score}</span>
                            </div>
                            <div className="h-2 rounded bg-slate-200 dark:bg-white/10 overflow-hidden">
                                <div className="h-full bg-violet-500/80" style={{ width: `${Math.max(0, Math.min(100, m.score))}%` }} />
                            </div>
                            <div className="mt-1 text-[11px] text-slate-500 dark:text-slate-400">วันว่าง {m.emptyDays} | กลุ่มซ้ำ {m.duplicates} | เคส {m.cases}</div>
                        </div>
                    ))}
                </div>
            </Card>

            <Card className="p-4 sm:p-5">
                <div className="flex flex-wrap items-center gap-2 text-sm font-semibold text-slate-800 dark:text-slate-200 mb-3">
                    <CalendarRange className="h-4 w-4 text-slate-500" />
                    ช่วงวันที่ตรวจสอบ
                </div>
                {monthOverviewMode && (
                    <div className="flex flex-wrap gap-2 mb-3">
                        <Button type="button" variant="outline" className="gap-1 px-3 py-2 text-xs" onClick={goPrevMonth}>
                            <ChevronLeft className="h-4 w-4" /> เดือนก่อน
                        </Button>
                        <Button type="button" variant="outline" className="px-3 py-2 text-xs" onClick={goThisMonth}>
                            เดือนนี้
                        </Button>
                        <Button type="button" variant="outline" className="gap-1 px-3 py-2 text-xs" onClick={goNextMonth}>
                            เดือนถัดไป <ChevronRight className="h-4 w-4" />
                        </Button>
                        <span className="text-xs text-slate-500 dark:text-slate-400 self-center ps-1">{monthLabelTH}</span>
                    </div>
                )}
                <div className="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-center">
                    <label className="flex items-center gap-2 text-sm">
                        <span className="text-slate-600 dark:text-slate-400 w-16 shrink-0">ตั้งแต่</span>
                        <input
                            type="date"
                            value={rangeStart}
                            onChange={e => setRangeStart(e.target.value)}
                            className="rounded-lg border border-slate-200 dark:border-white/15 bg-white dark:bg-white/5 px-3 py-2 text-slate-800 dark:text-slate-100"
                        />
                    </label>
                    <label className="flex items-center gap-2 text-sm">
                        <span className="text-slate-600 dark:text-slate-400 w-16 shrink-0">ถึง</span>
                        <input
                            type="date"
                            value={rangeEnd}
                            onChange={e => setRangeEnd(e.target.value)}
                            className="rounded-lg border border-slate-200 dark:border-white/15 bg-white dark:bg-white/5 px-3 py-2 text-slate-800 dark:text-slate-100"
                        />
                    </label>
                    <label className="flex items-center gap-2 text-sm cursor-pointer select-none">
                        <input
                            type="checkbox"
                            checked={hideSunday}
                            onChange={e => setHideSunday(e.target.checked)}
                            className="rounded border-slate-300 dark:border-white/20"
                        />
                        <span className="text-slate-700 dark:text-slate-300">ไม่นับวันอาทิตย์</span>
                    </label>
                    <label className="flex items-center gap-2 text-sm cursor-pointer select-none">
                        <input
                            type="checkbox"
                            checked={hidePublicHoliday}
                            onChange={e => setHidePublicHoliday(e.target.checked)}
                            className="rounded border-slate-300 dark:border-white/20"
                        />
                        <span className="text-slate-700 dark:text-slate-300">ซ่อนวันหยุดนักขัตฤกษ์</span>
                    </label>
                </div>
                <div className="mt-3 flex flex-wrap gap-2 text-xs">
                    <span className="text-slate-500 self-center">ตัวกรองความผิดปกติ:</span>
                    {([
                        ['all', 'ทั้งหมด'],
                        ['empty', 'ดูเฉพาะวันไม่มีบันทึก'],
                        ['duplicate', 'ดูเฉพาะวันซ้ำ'],
                    ] as Array<[DayFilterMode, string]>).map(([id, label]) => (
                        <button key={id} type="button" onClick={() => setDayFilterMode(id)} className={`rounded-full border px-3 py-1.5 font-medium ${dayFilterMode === id ? 'bg-slate-800 text-white dark:bg-amber-500/90 dark:text-slate-900 border-transparent' : 'border-slate-200 dark:border-white/15 text-slate-600 dark:text-slate-300'}`}>{label}</button>
                    ))}
                </div>
            </Card>

            <div className="grid gap-6">
                <Card className="p-4 sm:p-5 border-amber-200/80 dark:border-amber-500/25">
                    <div className="flex items-start gap-2 mb-3">
                        <AlertTriangle className="h-5 w-5 text-amber-600 dark:text-amber-400 shrink-0 mt-0.5" />
                        <div>
                            <h4 className="font-bold text-slate-800 dark:text-slate-100">ปฏิทินตรวจสอบ (คลิกวันที่เพื่อไป Daily Wizard)</h4>
                            <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
                                แดง = ไม่มีบันทึก, ส้ม = วันมีรายการซ้ำ, เขียว = ปกติ
                            </p>
                        </div>
                    </div>
                    <div className="grid grid-cols-7 gap-1.5 sm:gap-2 text-center text-xs">
                        {CALENDAR_WEEKDAY_TH.map(w => (
                            <div key={w} className="rounded-md bg-slate-100 dark:bg-white/[0.06] py-1 font-bold text-slate-600 dark:text-slate-300">
                                {w}
                            </div>
                        ))}
                        {calendarCells.map((cell, idx) => {
                            if (!cell) {
                                return <div key={`blank-${idx}`} className="h-11 sm:h-12 rounded-md bg-slate-50/60 dark:bg-white/[0.02]" />;
                            }
                            const base = 'h-11 sm:h-12 rounded-md flex items-center justify-center font-semibold';
                            const sundayClass = cell.isSunday ? ' ring-1 ring-red-200/70 dark:ring-red-500/30' : '';
                            const holidayClass = cell.isHoliday ? ' ring-1 ring-sky-200/70 dark:ring-sky-500/30' : '';
                            const matchFilter = dayFilterMode === 'all' || (dayFilterMode === 'empty' && cell.empty) || (dayFilterMode === 'duplicate' && cell.duplicate);
                            const dim = !matchFilter ? ' opacity-35' : '';
                            const openDailyWizard = () => {
                                if (!cell.inRange) return;
                                onGoToDailyWizard?.(cell.date);
                            };
                            if (!cell.inRange) {
                                return (
                                    <div key={cell.date} className={`${base} text-slate-300 dark:text-slate-600 bg-slate-50/70 dark:bg-white/[0.02]`}>
                                        {cell.day}
                                    </div>
                                );
                            }
                            if (cell.empty) {
                                return (
                                    <button type="button" onClick={openDailyWizard} key={cell.date} title={`ยังไม่มีบันทึก: ${formatDateBE(cell.date)}`} className={`${base} text-red-700 dark:text-red-200 bg-red-100 dark:bg-red-500/20 ${sundayClass} ${holidayClass}${dim}`}>
                                        {cell.day}
                                    </button>
                                );
                            }
                            if (cell.duplicate) {
                                return (
                                    <button type="button" onClick={openDailyWizard} key={cell.date} title={`พบความเสี่ยงข้อมูลซ้ำ: ${formatDateBE(cell.date)}`} className={`${base} text-orange-700 dark:text-orange-200 bg-orange-100 dark:bg-orange-500/20 ${sundayClass} ${holidayClass}${dim}`}>
                                        {cell.day}
                                    </button>
                                );
                            }
                            return (
                                <button type="button" onClick={openDailyWizard} key={cell.date} className={`${base} text-emerald-700 dark:text-emerald-300 bg-emerald-50 dark:bg-emerald-500/15 ${sundayClass} ${holidayClass}${dim}`}>
                                    {cell.day}
                                </button>
                            );
                        })}
                    </div>
                    <p className="mt-3 text-xs text-slate-500 dark:text-slate-400">
                        รวมวันไม่มีบันทึก {dayAnalysis.emptyDays.length} วัน | วันที่มีรายการซ้ำ {duplicateDaySet.size} วัน
                    </p>
                </Card>
            </div>

            <Card className="p-4 sm:p-5">
                <h4 className="font-bold text-slate-800 dark:text-slate-100 mb-1">กฎตรวจความสมเหตุสมผล (Rule Engine)</h4>
                <p className="text-xs text-slate-500 dark:text-slate-400 mb-3">ตัวอย่างกฎ: รายรับเป็น 0, ค่าแรงสูงผิดปกติ, น้ำมันมากแต่ไม่มีเที่ยวรถ (ปรับ threshold ได้จากการ์ดสรุป)</p>
                {ruleFindings.length === 0 ? (
                    <p className="text-sm text-emerald-700 dark:text-emerald-400 font-medium">ไม่พบความผิดปกติจากกฎในช่วงที่เลือก</p>
                ) : (
                    <ul className="space-y-2 max-h-64 overflow-y-auto">
                        {ruleFindings.map(f => (
                            <li key={f.id} className={`rounded-lg border p-2.5 text-sm ${f.severity === 'high' ? 'border-red-200 dark:border-red-500/30 bg-red-50/60 dark:bg-red-500/10' : 'border-amber-200 dark:border-amber-500/30 bg-amber-50/60 dark:bg-amber-500/10'}`}>
                                <div className="font-semibold text-slate-800 dark:text-slate-100">[{formatDateBE(f.date)}] {f.rule}</div>
                                <p className="text-xs text-slate-600 dark:text-slate-300 mt-0.5">{f.detail}</p>
                                <Button type="button" variant="outline" className="mt-2 px-2.5 py-1 text-xs" onClick={() => onGoToDailyWizard?.(f.date, 0)}>ไปตรวจใน Daily Wizard</Button>
                            </li>
                        ))}
                    </ul>
                )}
            </Card>

            <Card className="p-4 sm:p-5">
                <h4 className="font-bold text-slate-800 dark:text-slate-100 mb-1">รายการที่น่าสงสัยว่าซ้ำกัน</h4>
                <p className="text-xs text-slate-500 dark:text-slate-400 mb-4">
                    ตรวจทั้งแบบตรงกันทุกช่อง และแบบใกล้เคียงผิดปกติ (จำนวนเงิน/รายละเอียด/เวลา)
                </p>
                {duplicateClusterCount === 0 ? (
                    <p className="text-sm text-emerald-700 dark:text-emerald-400 font-medium">ไม่พบกลุ่มข้อมูลซ้ำในช่วงที่เลือก</p>
                ) : (
                    <ul className="space-y-3 max-h-80 overflow-y-auto">
                        {exactDuplicateClusters.map(({ key, items }) => {
                            const sample = items[0];
                            return (
                                <li key={key} className="rounded-xl border border-orange-200 dark:border-orange-500/30 bg-orange-50/50 dark:bg-orange-500/10 p-3 text-sm">
                                    <div className="font-semibold text-slate-800 dark:text-slate-100">
                                        [{formatDateBE(normalizeDate(sample.date))}] {sample.category}
                                        {sample.subCategory ? ` / ${sample.subCategory}` : ''} · {Number(sample.amount).toLocaleString()} บาท
                                    </div>
                                    <p className="text-xs text-slate-600 dark:text-slate-400 mt-1 line-clamp-2">{sample.description || '(ไม่มีรายละเอียด)'}</p>
                                    <p className="text-xs font-bold text-orange-800 dark:text-orange-200 mt-2">ซ้ำแบบตรงกัน พบ {items.length} รายการ</p>
                                    <Button type="button" variant="outline" className="mt-2 px-2.5 py-1 text-xs" onClick={() => onGoToDailyWizard?.(normalizeDate(sample.date), getStepByCategory(sample.category, sample.subCategory))}>ไปแก้ใน Daily Wizard</Button>
                                </li>
                            );
                        })}
                        {nearDuplicateFindings.map(f => (
                            <li key={f.id} className="rounded-xl border border-amber-200 dark:border-amber-500/30 bg-amber-50/40 dark:bg-amber-500/10 p-3 text-sm">
                                <div className="font-semibold text-slate-800 dark:text-slate-100">[{formatDateBE(f.date)}] {f.category}{f.subCategory ? ` / ${f.subCategory}` : ''}</div>
                                <p className="text-xs text-slate-600 dark:text-slate-400 mt-1">{f.reason} · {Number(f.amountA).toLocaleString()} vs {Number(f.amountB).toLocaleString()} บาท</p>
                                <p className="text-xs text-slate-500 dark:text-slate-400 mt-1">"{f.descA || '-'}" ↔ "{f.descB || '-'}"</p>
                                <Button type="button" variant="outline" className="mt-2 px-2.5 py-1 text-xs" onClick={() => onGoToDailyWizard?.(f.date, getStepByCategory(f.category, f.subCategory))}>ไปแก้ใน Daily Wizard</Button>
                            </li>
                        ))}
                    </ul>
                )}
            </Card>

            <Card className="p-4 sm:p-5">
                <h4 className="font-bold text-slate-800 dark:text-slate-100 mb-1">แจ้งเตือน / สงสัยข้อมูลผิดพลาด</h4>
                <p className="text-xs text-slate-500 dark:text-slate-400 mb-4">
                    สร้างเคสและติดตามสถานะได้ (ใหม่ / กำลังตรวจ / แก้แล้ว / ปิดเคส)
                </p>
                <div className="grid gap-3 sm:grid-cols-2 mb-3">
                    <label className="text-sm">
                        <span className="block text-slate-600 dark:text-slate-400 mb-1">วันที่อ้างอิง</span>
                        <input
                            type="date"
                            value={reportDate}
                            onChange={e => setReportDate(e.target.value)}
                            className="w-full rounded-lg border border-slate-200 dark:border-white/15 bg-white dark:bg-white/5 px-3 py-2 text-slate-800 dark:text-slate-100"
                        />
                    </label>
                </div>
                <textarea
                    value={reportBody}
                    onChange={e => setReportBody(e.target.value)}
                    rows={3}
                    placeholder="เช่น วันนี้กรอกเที่ยวรถซ้ำ 2 ครั้ง / สงสัยรายรับวันที่ผิด..."
                    className="w-full rounded-lg border border-slate-200 dark:border-white/15 bg-white dark:bg-white/5 px-3 py-2 text-sm text-slate-800 dark:text-slate-100 placeholder:text-slate-400 mb-3"
                />
                <Button type="button" onClick={submitReport} disabled={!reportBody.trim()}>
                    บันทึกการแจ้งเตือน
                </Button>
                <div className="mt-3">
                    <label className="text-xs text-slate-600 dark:text-slate-400">หมายเหตุเวลาปรับสถานะเคส (ใช้ร่วมกับทุกแถว)</label>
                    <input value={statusNote} onChange={e => setStatusNote(e.target.value)} placeholder="เช่น ตรวจข้อมูลย้อนหลังแล้วตรงกัน / แจ้งทีมแก้ไขแล้ว" className="mt-1 w-full rounded-lg border border-slate-200 dark:border-white/15 bg-white dark:bg-white/5 px-3 py-2 text-xs text-slate-800 dark:text-slate-100" />
                </div>

                {reports.length > 0 && (
                    <div className="mt-6 border-t border-slate-100 dark:border-white/10 pt-4">
                        <h5 className="text-sm font-bold text-slate-700 dark:text-slate-300 mb-2">รายการแจ้งเตือนที่บันทึกไว้</h5>
                        <ul className="space-y-2 max-h-56 overflow-y-auto">
                            {reports.map(r => (
                                <li key={r.id} className="flex gap-2 rounded-lg bg-slate-50 dark:bg-white/[0.04] p-3 text-sm">
                                    <div className="min-w-0 flex-1">
                                        <div className="font-semibold text-slate-800 dark:text-slate-100">
                                            วันที่อ้างอิง {formatDateBE(r.targetDate)}
                                        </div>
                                        <p className="text-slate-700 dark:text-slate-300 mt-1 whitespace-pre-wrap break-words">{r.body}</p>
                                        <p className="text-[11px] text-slate-500 mt-1">สร้าง: {r.createdAt}{r.adminName ? ` · ${r.adminName}` : ''}</p>
                                        {'updatedAt' in r && r.updatedAt ? <p className="text-[11px] text-slate-500">อัปเดตล่าสุด: {r.updatedAt}</p> : null}
                                    </div>
                                    <div className="flex flex-col gap-2">
                                        <select value={(r.status || 'new') as ReportStatus} onChange={e => updateReportStatus(r.id, e.target.value as ReportStatus, statusNote)} className="rounded border border-slate-200 dark:border-white/20 bg-white dark:bg-white/5 px-2 py-1 text-xs">
                                            <option value="new">ใหม่</option>
                                            <option value="investigating">กำลังตรวจ</option>
                                            <option value="resolved">แก้แล้ว</option>
                                            <option value="closed">ปิดเคส</option>
                                        </select>
                                        <button
                                            type="button"
                                            onClick={() => removeReport(r.id)}
                                            className="shrink-0 self-start p-2 rounded-lg text-slate-400 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-500/10"
                                            title="ลบรายการนี้"
                                        >
                                            <Trash2 className="h-4 w-4" />
                                        </button>
                                    </div>
                                </li>
                            ))}
                        </ul>
                    </div>
                )}
            </Card>

            <Card className="p-4 sm:p-5">
                <h4 className="font-bold text-slate-800 dark:text-slate-100 mb-1">Audit Trail ของเคสตรวจสอบ</h4>
                <p className="text-xs text-slate-500 dark:text-slate-400 mb-3">บันทึกว่าใครเปลี่ยนสถานะจากอะไรไปอะไร เมื่อไร และหมายเหตุ</p>
                {auditTrail.length === 0 ? (
                    <p className="text-sm text-slate-500 dark:text-slate-400">ยังไม่มีประวัติการเปลี่ยนสถานะ</p>
                ) : (
                    <ul className="space-y-2 max-h-56 overflow-y-auto">
                        {auditTrail.map(a => (
                            <li key={a.id} className="rounded-lg border border-slate-100 dark:border-white/10 bg-slate-50/70 dark:bg-white/[0.03] p-2.5 text-xs">
                                <div className="font-semibold text-slate-700 dark:text-slate-300">{formatDateBE(a.reportDate)} · {a.changedByAdminName || '-'} · {(a.fromStatus && REPORT_STATUS_LABEL[a.fromStatus]) || '-'} → {REPORT_STATUS_LABEL[a.toStatus]}</div>
                                <div className="text-slate-500 dark:text-slate-400 mt-0.5">{a.changedAt}{a.note ? ` · หมายเหตุ: ${a.note}` : ''}</div>
                            </li>
                        ))}
                    </ul>
                )}
            </Card>
        </div>
    );
};

export default DataVerificationModule;
