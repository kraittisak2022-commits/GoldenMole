import { useMemo, useState, useCallback, useEffect } from 'react';
import { AlertTriangle, CalendarRange, ClipboardCheck, Trash2, ChevronLeft, ChevronRight, FileDown, Printer, GitBranch, CheckCircle2, Timer, Sparkles } from 'lucide-react';
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
    // Vehicle category: same day with different vehicles/drivers is normal, not duplicate.
    const vehicleScope = t.category === 'Vehicle'
        ? `|veh:${t.vehicleId || '-'}|drv:${t.driverId || '-'}`
        : '';
    return `${d}|${t.category}|${sub}|${t.amount}|${desc}${vehicleScope}`;
};

const buildExactDuplicateFixGuide = (items: Transaction[]) => {
    const ids = items.map(i => i.id).join(', ');
    return {
        why: 'ระบบพบรายการที่วัน/หมวด/หมวดย่อย/จำนวนเงิน/รายละเอียด ตรงกันทุกช่อง',
        howToFix: 'ตรวจว่าเป็นการบันทึกซ้ำจริงหรือไม่: ถ้าซ้ำให้ลบรายการที่เกิน, ถ้าตั้งใจแยกรายการให้แก้รายละเอียดหรือจำนวนเงินให้ต่างกันชัดเจน',
        ids,
    };
};

const buildNearDuplicateFixGuide = (reason: string) => {
    if (reason.includes('เวลาใกล้กัน')) {
        return 'ตรวจเวลาและรายการอ้างอิงหน้างาน: ถ้าเป็นงานเดียวกันให้รวมเป็นรายการเดียว, ถ้าคนละงานให้ใส่รายละเอียดแยกจุดงาน/รอบงานให้ชัด';
    }
    if (reason.includes('รายละเอียดใกล้เคียง')) {
        return 'ตรวจคำอธิบาย: ถ้าหมายถึงเหตุการณ์เดียวกันให้ลบตัวที่ซ้ำ, ถ้าคนละเหตุการณ์ให้เพิ่มเลขรถ/ชื่อพนักงาน/สถานที่ในรายละเอียด';
    }
    return 'ตรวจหลักฐานหน้างานและยอดเงินจริง: ถ้าซ้ำให้ลบรายการซ้ำ, ถ้าไม่ซ้ำให้ปรับคำอธิบายหรือจำนวนเงินให้แยกจากกันชัดเจน';
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
const toProgressPercent = (value: number, target: number) => {
    if (target <= 0) return value > 0 ? 100 : 0;
    return Math.max(0, Math.min(100, (value / target) * 100));
};

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
    const [roundTargetCubic, setRoundTargetCubic] = useState(800);
    const [roundTargetDays, setRoundTargetDays] = useState(2);
    const [roundTargetDrums, setRoundTargetDrums] = useState(52);
    const [roundCloseMinDays, setRoundCloseMinDays] = useState(2);
    const [selectedRoundId, setSelectedRoundId] = useState('');
    const [selectedFlowStep, setSelectedFlowStep] = useState<'transport' | 'wash' | 'obtained' | 'home'>('transport');
    const [isFlowStepModalOpen, setIsFlowStepModalOpen] = useState(false);
    const [alertAgingDays, setAlertAgingDays] = useState(3);
    const [workflowReason, setWorkflowReason] = useState('');
    const [batchEditDrafts, setBatchEditDrafts] = useState<Record<string, string>>({});
    const [mergeSourceBatchId, setMergeSourceBatchId] = useState('');
    const [mergeTargetBatchId, setMergeTargetBatchId] = useState('');

    const reports = settings.appDefaults?.dataQualityReports || [];
    const auditTrail = settings.appDefaults?.dataQualityAuditTrail || [];
    const sandBatchAllocations = settings.appDefaults?.sandHomeBatchAllocations || [];
    const sandRoundAuditTrail = settings.appDefaults?.sandRoundAuditTrail || [];
    const sandRoundWorkflowById = settings.appDefaults?.sandRoundWorkflowById || {};
    const sandOpsNotificationRules = settings.appDefaults?.sandOpsNotificationRules || {};
    const canManageSandRounds = currentAdmin?.role === 'SuperAdmin' || currentAdmin?.role === 'Admin';
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
    const sandRoundOverview = useMemo(() => {
        const dateSet = new Set(datesInRange);
        const dailyMap = new Map<string, { transported: number; washed: number; obtained: number; home: number }>();

        transactions.forEach(t => {
            const d = normalizeDate(t.date);
            if (!dateSet.has(d)) return;
            const daily = dailyMap.get(d) || { transported: 0, washed: 0, obtained: 0, home: 0 };

            if (t.category === 'DailyLog' && t.subCategory === 'VehicleTrip') {
                const tripCubic = Number(t.totalCubic || t.quantity || 0);
                daily.transported += Math.max(0, tripCubic);
            }

            if (t.category === 'DailyLog' && t.subCategory === 'Sand') {
                const washed = (Number(t.sandMorning) || 0) + (Number(t.sandAfternoon) || 0);
                daily.washed += Math.max(0, washed);
                const obtained = Math.max(0, Number((t as any).drumsObtained || 0));
                daily.obtained = Math.max(daily.obtained, obtained);
                const homeFromSand = Math.max(0, Number((t as any).drumsWashedAtHome || 0));
                daily.home = Math.max(daily.home, homeFromSand);
            }

            if (t.category === 'Labor') {
                const homeFromLabor = Math.max(0, Number((t as any).drumsWashedAtHome || 0));
                if (homeFromLabor > 0) {
                    daily.home = Math.max(daily.home, homeFromLabor);
                }
            }
            dailyMap.set(d, daily);
        });

        const dailyRows = Array.from(dailyMap.entries())
            .map(([date, v]) => ({ date, ...v }))
            .sort((a, b) => a.date.localeCompare(b.date));

        let transportedCubic = 0;
        let washedCubic = 0;
        let washDays = 0;
        let obtainedDrums = 0;
        let washedHomeDrums = 0;
        dailyRows.forEach(r => {
            transportedCubic += r.transported;
            washedCubic += r.washed;
            if (r.washed > 0) washDays += 1;
            obtainedDrums += r.obtained;
            washedHomeDrums += r.home;
        });

        type RoundDay = { date: string; transported: number; washed: number; obtained: number; home: number };
        type SandRound = {
            id: string;
            roundNo: number;
            startDate: string;
            endDate: string;
            transportedCubic: number;
            washedCubic: number;
            washDays: number;
            obtainedDrums: number;
            washedHomeDrums: number;
            remainingDrums: number;
            completed: boolean;
            forceClosed: boolean;
            completionReason?: string;
            days: RoundDay[];
        };
        const forceClosedRoundIds = new Set(
            (sandRoundAuditTrail || [])
                .filter(a => a.action === 'manual_close_round')
                .map(a => a.roundId),
        );
        const rounds: SandRound[] = [];
        let roundNo = 0;
        let current: SandRound | null = null;

        dailyRows.forEach(r => {
            const active = r.transported > 0 || r.washed > 0 || r.obtained > 0 || r.home > 0;
            if (!active) return;
            if (!current) {
                roundNo += 1;
                current = {
                    id: `round_${roundNo}_${r.date}`,
                    roundNo,
                    startDate: r.date,
                    endDate: r.date,
                    transportedCubic: 0,
                    washedCubic: 0,
                    washDays: 0,
                    obtainedDrums: 0,
                    washedHomeDrums: 0,
                    remainingDrums: 0,
                    completed: false,
                    forceClosed: false,
                    days: [],
                };
            }

            current.endDate = r.date;
            current.transportedCubic += r.transported;
            current.washedCubic += r.washed;
            if (r.washed > 0) current.washDays += 1;
            current.obtainedDrums += r.obtained;
            current.washedHomeDrums += r.home;
            current.remainingDrums = Math.max(0, current.obtainedDrums - current.washedHomeDrums);
            current.days.push(r);

            // ปิดรอบเมื่อถังคงเหลือที่บ้านเป็น 0 และครบจำนวนวันขั้นต่ำของรอบ
            const isAutoCompleted =
                current.remainingDrums === 0 &&
                current.obtainedDrums > 0 &&
                current.days.length >= Math.max(1, roundCloseMinDays);
            const isForceClosed = forceClosedRoundIds.has(current.id);
            const isCompleted = isAutoCompleted || isForceClosed;

            if (isCompleted) {
                current.completed = true;
                current.forceClosed = isForceClosed;
                current.completionReason = isForceClosed ? 'ปิดรอบด้วยสิทธิ์ผู้ดูแล' : 'ปิดรอบอัตโนมัติ (คงเหลือถัง = 0)';
                rounds.push(current);
                current = null;
            }
        });

        if (current) {
            rounds.push(current);
        }

        const latestRound = rounds[rounds.length - 1] || null;
        const remainingDrums = latestRound ? latestRound.remainingDrums : Math.max(0, obtainedDrums - washedHomeDrums);

        const completed = remainingDrums === 0 && obtainedDrums > 0;

        return {
            transportedCubic,
            washDays,
            washedCubic,
            obtainedDrums,
            washedHomeDrums,
            remainingDrums,
            completed,
            rounds,
            latestRound,
        };
    }, [datesInRange, transactions, roundTargetCubic, roundTargetDays, roundTargetDrums, roundCloseMinDays, sandRoundAuditTrail]);
    useEffect(() => {
        if (sandRoundOverview.rounds.length === 0) {
            if (selectedRoundId) setSelectedRoundId('');
            return;
        }
        const exists = sandRoundOverview.rounds.some(r => r.id === selectedRoundId);
        if (!exists) {
            setSelectedRoundId(sandRoundOverview.rounds[sandRoundOverview.rounds.length - 1].id);
        }
    }, [sandRoundOverview.rounds, selectedRoundId]);
    useEffect(() => {
        const ruleDays = Math.max(1, Number(sandOpsNotificationRules.agingDays || 0));
        if (ruleDays > 0 && ruleDays !== alertAgingDays) setAlertAgingDays(ruleDays);
    }, [sandOpsNotificationRules.agingDays, alertAgingDays]);
    const selectedRound = useMemo(() => {
        return sandRoundOverview.rounds.find(r => r.id === selectedRoundId) || sandRoundOverview.latestRound || null;
    }, [sandRoundOverview.rounds, sandRoundOverview.latestRound, selectedRoundId]);
    const selectedRoundWorkflowStatus = selectedRound
        ? (sandRoundWorkflowById[selectedRound.id]?.status || (selectedRound.completed ? 'Closed' : 'Open'))
        : 'Open';
    const isBatchImmutable = selectedRoundWorkflowStatus === 'Closed';
    const selectedRoundTraceRowsAuto = useMemo(() => {
        if (!selectedRound) return [];
        type SourceBatch = { sourceDate: string; remaining: number; linkedTransportDate?: string };
        const transportDates = selectedRound.days
            .filter(d => d.transported > 0)
            .map(d => d.date)
            .sort((a, b) => a.localeCompare(b));
        const sourceQueue: SourceBatch[] = [];
        const rows: Array<{
            id?: string;
            homeDate: string;
            sourceDate: string;
            linkedTransportDate?: string;
            drums: number;
            batchId: string;
        }> = [];
        const getLinkedTransportDate = (sourceDate: string) => {
            const eligible = transportDates.filter(d => d <= sourceDate);
            return eligible.length > 0 ? eligible[eligible.length - 1] : transportDates[0];
        };

        selectedRound.days.forEach(d => {
            if (d.obtained > 0) {
                sourceQueue.push({
                    sourceDate: d.date,
                    remaining: d.obtained,
                    linkedTransportDate: getLinkedTransportDate(d.date),
                });
            }
            let toAllocate = d.home;
            while (toAllocate > 0 && sourceQueue.length > 0) {
                const current = sourceQueue[0];
                const used = Math.min(toAllocate, current.remaining);
                rows.push({
                    homeDate: d.date,
                    sourceDate: current.sourceDate,
                    linkedTransportDate: current.linkedTransportDate,
                    drums: used,
                    batchId: `BATCH-${current.sourceDate.replace(/-/g, '')}`,
                });
                current.remaining -= used;
                toAllocate -= used;
                if (current.remaining <= 0) sourceQueue.shift();
            }
        });
        return rows;
    }, [selectedRound]);
    const selectedRoundTraceRows = useMemo(() => {
        if (!selectedRound) return [];
        const manualRows = sandBatchAllocations.filter(a => a.roundId === selectedRound.id);
        if (manualRows.length === 0) return selectedRoundTraceRowsAuto;
        return manualRows
            .map(a => ({
                homeDate: a.homeDate,
                sourceDate: a.sourceDate,
                linkedTransportDate: a.linkedTransportDate,
                drums: Number(a.drums || 0),
                batchId: a.batchId || `BATCH-${String(a.sourceDate || '').replace(/-/g, '')}`,
                id: a.id,
            }))
            .sort((a, b) => a.homeDate.localeCompare(b.homeDate));
    }, [selectedRound, sandBatchAllocations, selectedRoundTraceRowsAuto]);
    const roundTimeline = useMemo(() => {
        if (!selectedRound) return [];
        return selectedRound.days
            .map(d => {
                const tags: string[] = [];
                if (d.transported > 0) tags.push(`ขนทราย ${d.transported.toLocaleString()} คิว`);
                if (d.washed > 0) tags.push(`ล้าง ${d.washed.toLocaleString()} คิว`);
                if (d.obtained > 0) tags.push(`ได้ ${d.obtained.toLocaleString()} ถัง`);
                if (d.home > 0) tags.push(`ล้างที่บ้าน ${d.home.toLocaleString()} ถัง`);
                return { date: d.date, tags };
            })
            .filter(r => r.tags.length > 0);
    }, [selectedRound]);
    const selectedRoundAutoAlerts = useMemo(() => {
        if (!selectedRound) return [];
        const alerts: Array<{ id: string; severity: 'high' | 'medium'; text: string }> = [];
        selectedRound.days.forEach(d => {
            if (d.home > d.obtained + selectedRound.remainingDrums) {
                alerts.push({ id: `home_gt_stock_${d.date}`, severity: 'high', text: `${formatDateBE(d.date)} ล้างที่บ้านมากกว่าถังที่มีในระบบ` });
            }
            if (d.obtained > 0 && d.transported <= 0) {
                alerts.push({ id: `no_transport_${d.date}`, severity: 'medium', text: `${formatDateBE(d.date)} ได้ถังแต่ไม่พบข้อมูลขนทรายเข้า` });
            }
        });
        const unwashedSources = selectedRound.days.filter(d => d.obtained > 0).map(d => d.date);
        const washedSourceSet = new Set(selectedRoundTraceRows.map(r => r.sourceDate));
        unwashedSources.forEach(sd => {
            if (washedSourceSet.has(sd)) return;
            const age = enumerateDates(sd, selectedRound.endDate).length - 1;
            if (age >= alertAgingDays) {
                alerts.push({
                    id: `aging_${sd}`,
                    severity: 'medium',
                    text: `ล็อต ${sd.replace(/-/g, '')} ค้างเกิน ${alertAgingDays} วัน (ยังไม่ถูกล้างที่บ้าน)`,
                });
            }
        });
        return alerts;
    }, [selectedRound, selectedRoundTraceRows, alertAgingDays]);
    const notificationAckIds = settings.appDefaults?.sandOpsNotificationAckIds || [];
    const sandOpsInbox = useMemo(() => {
        const items: Array<{ id: string; roundId: string; severity: 'high' | 'medium'; text: string }> = [];
        sandRoundOverview.rounds.forEach(r => {
            const yieldRatio = r.washedCubic > 0 ? r.obtainedDrums / r.washedCubic : 0;
            if (r.remainingDrums > 0 && r.washDays >= alertAgingDays) {
                items.push({
                    id: `remain_${r.id}`,
                    roundId: r.id,
                    severity: 'medium',
                    text: `รอบ ${r.roundNo}: ถังค้าง ${r.remainingDrums.toLocaleString()} ถัง เกิน ${alertAgingDays} วัน`,
                });
            }
            if (yieldRatio > 0 && yieldRatio < 0.02) {
                items.push({
                    id: `yield_low_${r.id}`,
                    roundId: r.id,
                    severity: 'medium',
                    text: `รอบ ${r.roundNo}: yield ต่ำ (${yieldRatio.toFixed(3)} ถัง/คิว)`,
                });
            }
            if (r.obtainedDrums > 0 && r.transportedCubic <= 0) {
                items.push({
                    id: `transport_missing_${r.id}`,
                    roundId: r.id,
                    severity: 'high',
                    text: `รอบ ${r.roundNo}: มีถังที่ได้ แต่ไม่พบข้อมูลขนทราย`,
                });
            }
        });
        return items;
    }, [sandRoundOverview.rounds, alertAgingDays]);
    const unackedSandOpsInbox = useMemo(
        () => sandOpsInbox.filter(i => !notificationAckIds.includes(i.id)),
        [sandOpsInbox, notificationAckIds],
    );
    const selectedRoundHighUnacked = useMemo(() => {
        if (!selectedRound) return 0;
        return unackedSandOpsInbox.filter(i => i.roundId === selectedRound.id && i.severity === 'high').length;
    }, [selectedRound, unackedSandOpsInbox]);
    const acknowledgeNotification = useCallback((id: string) => {
        setSettings(prev => ({
            ...prev,
            appDefaults: {
                ...(prev.appDefaults || {}),
                sandOpsNotificationAckIds: Array.from(new Set([...(prev.appDefaults?.sandOpsNotificationAckIds || []), id])),
            },
        }));
    }, [setSettings]);
    const createRoundAudit = useCallback((roundId: string, action: 'manual_close_round' | 'edit_batch_allocation' | 'create_batch_allocation' | 'delete_batch_allocation', note?: string) => {
        setSettings(prev => ({
            ...prev,
            appDefaults: {
                ...(prev.appDefaults || {}),
                sandRoundAuditTrail: [{
                    id: `${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
                    roundId,
                    action,
                    note,
                    adminId: currentAdmin?.id,
                    adminName: currentAdmin?.displayName || currentAdmin?.username,
                    createdAt: formatDateTimeTH(),
                }, ...(prev.appDefaults?.sandRoundAuditTrail || [])].slice(0, 1000),
            },
        }));
    }, [setSettings, currentAdmin]);
    const closeRoundManually = useCallback((roundId: string) => {
        if (!canManageSandRounds) return;
        createRoundAudit(roundId, 'manual_close_round', 'ปิดรอบด้วยสิทธิ์ผู้ดูแล');
    }, [canManageSandRounds, createRoundAudit]);
    const updateRoundWorkflow = useCallback((roundId: string, status: 'Open' | 'Reviewing' | 'Closed' | 'Reopened', reason?: string) => {
        if (!canManageSandRounds) return;
        const note = reason?.trim() || '';
        if ((status === 'Closed' || status === 'Reopened') && !note) {
            window.alert(`กรุณาระบุเหตุผลก่อนเปลี่ยนสถานะเป็น ${status}`);
            return;
        }
        setSettings(prev => ({
            ...prev,
            appDefaults: {
                ...(prev.appDefaults || {}),
                sandRoundWorkflowById: {
                    ...(prev.appDefaults?.sandRoundWorkflowById || {}),
                    [roundId]: {
                        status,
                        reason: note || undefined,
                        approvedByAdminId: currentAdmin?.id,
                        approvedByAdminName: currentAdmin?.displayName || currentAdmin?.username,
                        updatedAt: formatDateTimeTH(),
                    },
                },
            },
        }));
        createRoundAudit(roundId, 'manual_close_round', `workflow=${status}${note ? ` (${note})` : ''}`);
    }, [canManageSandRounds, setSettings, currentAdmin, createRoundAudit]);
    const updateNotificationRules = useCallback((days: number) => {
        setSettings(prev => ({
            ...prev,
            appDefaults: {
                ...(prev.appDefaults || {}),
                sandOpsNotificationRules: {
                    ...(prev.appDefaults?.sandOpsNotificationRules || {}),
                    agingDays: Math.max(1, days),
                },
            },
        }));
    }, [setSettings]);
    const updateBatchId = useCallback((row: { id?: string; batchId: string; homeDate: string; sourceDate: string; linkedTransportDate?: string; drums: number }) => {
        if (!canManageSandRounds || !selectedRound || isBatchImmutable) return;
        const trimmed = row.batchId.trim();
        if (!trimmed) return;
        const existingId = row.id || `${selectedRound.id}_${row.homeDate}_${row.sourceDate}_${row.drums}`;
        setSettings(prev => {
            const old = prev.appDefaults?.sandHomeBatchAllocations || [];
            const others = old.filter(a => a.id !== existingId);
            const next = {
                id: existingId,
                roundId: selectedRound.id,
                homeDate: row.homeDate,
                sourceDate: row.sourceDate,
                linkedTransportDate: row.linkedTransportDate,
                drums: row.drums,
                batchId: trimmed,
                createdAt: old.find(a => a.id === existingId)?.createdAt || formatDateTimeTH(),
                createdByAdminId: old.find(a => a.id === existingId)?.createdByAdminId || currentAdmin?.id,
                createdByAdminName: old.find(a => a.id === existingId)?.createdByAdminName || currentAdmin?.displayName || currentAdmin?.username,
                updatedAt: formatDateTimeTH(),
                updatedByAdminId: currentAdmin?.id,
                updatedByAdminName: currentAdmin?.displayName || currentAdmin?.username,
            };
            return {
                ...prev,
                appDefaults: {
                    ...(prev.appDefaults || {}),
                    sandHomeBatchAllocations: [next, ...others].slice(0, 2000),
                },
            };
        });
        const before = row.id ? (sandBatchAllocations.find(a => a.id === row.id)?.batchId || '-') : '-';
        createRoundAudit(selectedRound.id, row.id ? 'edit_batch_allocation' : 'create_batch_allocation', `batch ${before} -> ${trimmed} | ${row.homeDate}<=${row.sourceDate}`);
    }, [canManageSandRounds, selectedRound, setSettings, currentAdmin, createRoundAudit, sandBatchAllocations, isBatchImmutable]);
    const deleteBatchAllocation = useCallback((rowId?: string) => {
        if (!canManageSandRounds || !selectedRound || isBatchImmutable || !rowId) return;
        const before = sandBatchAllocations.find(a => a.id === rowId);
        setSettings(prev => ({
            ...prev,
            appDefaults: {
                ...(prev.appDefaults || {}),
                sandHomeBatchAllocations: (prev.appDefaults?.sandHomeBatchAllocations || []).filter(a => a.id !== rowId),
            },
        }));
        createRoundAudit(selectedRound.id, 'delete_batch_allocation', `delete batch=${before?.batchId || '-'} ${before?.homeDate || '-'}<=${before?.sourceDate || '-'}`);
    }, [canManageSandRounds, selectedRound, isBatchImmutable, sandBatchAllocations, setSettings, createRoundAudit]);
    const mergeBatchInRound = useCallback(() => {
        if (!canManageSandRounds || !selectedRound || isBatchImmutable) return;
        const from = mergeSourceBatchId.trim();
        const to = mergeTargetBatchId.trim();
        if (!from || !to || from === to) return;
        const affected = sandBatchAllocations.filter(a => a.roundId === selectedRound.id && a.batchId === from);
        if (affected.length === 0) return;
        setSettings(prev => ({
            ...prev,
            appDefaults: {
                ...(prev.appDefaults || {}),
                sandHomeBatchAllocations: (prev.appDefaults?.sandHomeBatchAllocations || []).map(a => {
                    if (a.roundId !== selectedRound.id) return a;
                    if (a.batchId !== from) return a;
                    return { ...a, batchId: to, updatedAt: formatDateTimeTH(), updatedByAdminId: currentAdmin?.id, updatedByAdminName: currentAdmin?.displayName || currentAdmin?.username };
                }),
            },
        }));
        createRoundAudit(selectedRound.id, 'edit_batch_allocation', `merge batch ${from} -> ${to} (${affected.length} rows)`);
        setMergeSourceBatchId('');
        setMergeTargetBatchId('');
    }, [canManageSandRounds, selectedRound, isBatchImmutable, mergeSourceBatchId, mergeTargetBatchId, sandBatchAllocations, setSettings, currentAdmin, createRoundAudit]);
    const selectedFlowStepDetail = useMemo(() => {
        if (!selectedRound) return null;
        if (selectedFlowStep === 'transport') {
            const rows = selectedRound.days.filter(d => d.transported > 0);
            return {
                title: 'รายละเอียดขั้นขนทรายเข้า',
                subtitle: `รวม ${selectedRound.transportedCubic.toLocaleString()} คิว`,
                rows: rows.map(d => `${formatDateBE(d.date)} ขนทรายเข้า ${d.transported.toLocaleString()} คิว`),
            };
        }
        if (selectedFlowStep === 'wash') {
            const rows = selectedRound.days.filter(d => d.washed > 0);
            return {
                title: 'รายละเอียดขั้นล้างทราย',
                subtitle: `ล้าง ${selectedRound.washDays} วัน รวม ${selectedRound.washedCubic.toLocaleString()} คิว`,
                rows: rows.map(d => `${formatDateBE(d.date)} ล้าง ${d.washed.toLocaleString()} คิว`),
            };
        }
        if (selectedFlowStep === 'obtained') {
            const rows = selectedRound.days.filter(d => d.obtained > 0);
            return {
                title: 'รายละเอียดขั้นได้ถัง',
                subtitle: `รวม ${selectedRound.obtainedDrums.toLocaleString()} ถัง`,
                rows: rows.map(d => `${formatDateBE(d.date)} ได้ถัง ${d.obtained.toLocaleString()} ถัง`),
            };
        }
        const rows = selectedRound.days.filter(d => d.home > 0);
        return {
            title: 'รายละเอียดขั้นล้างที่บ้าน',
            subtitle: `ล้างที่บ้านรวม ${selectedRound.washedHomeDrums.toLocaleString()} ถัง`,
            rows: rows.map(d => `${formatDateBE(d.date)} ล้างที่บ้าน ${d.home.toLocaleString()} ถัง`),
        };
    }, [selectedRound, selectedFlowStep]);
    const selectedRoundDelta = useMemo(() => {
        if (!selectedRound) return null;
        const idx = sandRoundOverview.rounds.findIndex(r => r.id === selectedRound.id);
        if (idx <= 0) return null;
        const prev = sandRoundOverview.rounds[idx - 1];
        const curYield = selectedRound.washedCubic > 0 ? selectedRound.obtainedDrums / selectedRound.washedCubic : 0;
        const prevYield = prev.washedCubic > 0 ? prev.obtainedDrums / prev.washedCubic : 0;
        return {
            dayDelta: selectedRound.washDays - prev.washDays,
            yieldDeltaPct: prevYield > 0 ? ((curYield - prevYield) / prevYield) * 100 : 0,
            prevRoundNo: prev.roundNo,
        };
    }, [selectedRound, sandRoundOverview.rounds]);
    const openFlowStepDetail = (step: 'transport' | 'wash' | 'obtained' | 'home') => {
        setSelectedFlowStep(step);
        setIsFlowStepModalOpen(true);
    };

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
            // Vehicle category: compare near-duplicates within same vehicle/driver only.
            const key = t.category === 'Vehicle'
                ? `${td}|${t.category}|${t.subCategory || ''}|veh:${t.vehicleId || '-'}|drv:${t.driverId || '-'}`
                : `${td}|${t.category}|${t.subCategory || ''}`;
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
    const exactDuplicateDaySet = useMemo(() => {
        const s = new Set<string>();
        exactDuplicateClusters.forEach(c => s.add(normalizeDate(c.items[0].date)));
        return s;
    }, [exactDuplicateClusters]);
    const nearDuplicateDaySet = useMemo(() => {
        const s = new Set<string>();
        nearDuplicateFindings.forEach(f => s.add(f.date));
        return s;
    }, [nearDuplicateFindings]);
    const duplicateDaySet = useMemo(() => {
        const s = new Set<string>(exactDuplicateDaySet);
        nearDuplicateDaySet.forEach(d => s.add(d));
        return s;
    }, [exactDuplicateDaySet, nearDuplicateDaySet]);
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
        const cells: Array<{ date: string; day: number; inRange: boolean; empty: boolean; duplicate: boolean; nearDuplicate: boolean; isSunday: boolean; isHoliday: boolean } | null> = [];
        for (let i = 0; i < firstWeekday; i += 1) cells.push(null);
        for (const d of monthDates) {
            const day = Number(d.slice(8, 10));
            cells.push({
                date: d,
                day,
                inRange: rangeSet.has(d),
                empty: emptySet.has(d),
                duplicate: exactDuplicateDaySet.has(d),
                nearDuplicate: nearDuplicateDaySet.has(d),
                isSunday: isSunday(d),
                isHoliday: isThaiHoliday(d),
            });
        }
        while (cells.length % 7 !== 0) cells.push(null);
        return cells;
    }, [rangeStart, datesInRange, dayAnalysis.emptyDays, exactDuplicateDaySet, nearDuplicateDaySet, isThaiHoliday]);

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
    const exportSelectedRoundCsv = () => {
        if (!selectedRound) return;
        const rows: string[][] = [];
        rows.push(['รอบ', String(selectedRound.roundNo)]);
        rows.push(['ช่วงวันที่', `${selectedRound.startDate} - ${selectedRound.endDate}`]);
        rows.push(['ขนทรายรวม(คิว)', String(selectedRound.transportedCubic)]);
        rows.push(['ล้างทรายรวม(คิว)', String(selectedRound.washedCubic)]);
        rows.push(['ได้ถังรวม', String(selectedRound.obtainedDrums)]);
        rows.push(['ล้างที่บ้านรวม', String(selectedRound.washedHomeDrums)]);
        rows.push(['คงเหลือ', String(selectedRound.remainingDrums)]);
        rows.push([]);
        rows.push(['timeline']);
        rows.push(['date', 'events']);
        roundTimeline.forEach(t => rows.push([t.date, t.tags.join(' | ')]));
        rows.push([]);
        rows.push(['trace']);
        rows.push(['homeDate', 'sourceDate', 'transportDate', 'batchId', 'drums']);
        selectedRoundTraceRows.forEach(r => rows.push([r.homeDate, r.sourceDate, r.linkedTransportDate || '-', r.batchId || '-', String(r.drums)]));
        const csv = rows.map(cols => cols.map(v => `"${String(v || '').replace(/"/g, '""')}"`).join(',')).join('\n');
        const blob = new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `sand-round-${selectedRound.roundNo}-${selectedRound.startDate}-to-${selectedRound.endDate}.csv`;
        a.click();
        URL.revokeObjectURL(url);
    };
    const printSelectedRound = () => {
        if (!selectedRound) return;
        const html = `<!doctype html><html><head><meta charset="utf-8"/><title>Sand Round Report</title><style>body{font-family:Arial,sans-serif;padding:20px}h1{font-size:18px}table{width:100%;border-collapse:collapse;margin-top:10px}th,td{border:1px solid #ccc;padding:6px;font-size:12px;text-align:left}</style></head><body><h1>รายงานรอบล้างทราย #${selectedRound.roundNo}</h1><p>ช่วง ${selectedRound.startDate} ถึง ${selectedRound.endDate}</p><table><thead><tr><th>หัวข้อ</th><th>ค่า</th></tr></thead><tbody><tr><td>ขนทรายรวม</td><td>${selectedRound.transportedCubic.toLocaleString()} คิว</td></tr><tr><td>ล้างทรายรวม</td><td>${selectedRound.washedCubic.toLocaleString()} คิว</td></tr><tr><td>ได้ถังรวม</td><td>${selectedRound.obtainedDrums.toLocaleString()} ถัง</td></tr><tr><td>ล้างที่บ้านรวม</td><td>${selectedRound.washedHomeDrums.toLocaleString()} ถัง</td></tr><tr><td>คงเหลือ</td><td>${selectedRound.remainingDrums.toLocaleString()} ถัง</td></tr></tbody></table><h2 style="font-size:14px;margin-top:16px">Trace Batch</h2><table><thead><tr><th>ล้างที่บ้าน</th><th>ทรายจากล้าง</th><th>ขนเข้า</th><th>Batch</th><th>ถัง</th></tr></thead><tbody>${selectedRoundTraceRows.map(r => `<tr><td>${r.homeDate}</td><td>${r.sourceDate}</td><td>${r.linkedTransportDate || '-'}</td><td>${r.batchId || '-'}</td><td>${r.drums}</td></tr>`).join('')}</tbody></table></body></html>`;
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

            <Card className="p-4 sm:p-5 border-cyan-200/80 dark:border-cyan-500/25 bg-gradient-to-br from-cyan-50/80 via-white to-sky-50/70 dark:from-cyan-500/10 dark:via-slate-900 dark:to-sky-500/10 shadow-md hover:shadow-xl transition-all duration-300">
                <div className="flex items-start gap-2">
                    <GitBranch className="h-5 w-5 text-cyan-600 dark:text-cyan-300 shrink-0 mt-0.5 animate-pulse" />
                    <div className="min-w-0">
                        <h4 className="text-sm font-bold text-slate-800 dark:text-slate-100">ระบบตรวจสอบรอบล้างทราย (Flowchart)</h4>
                        <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">ตัวอย่างรอบงาน: ขนทราย 800 คิว → ล้าง 2 วัน → ได้ 52 ถัง → ล้างที่บ้านครบ 52 ถัง = สรุปรอบ</p>
                    </div>
                </div>
                <div className="mt-3 grid gap-2 sm:grid-cols-3 text-xs">
                    <label className="flex items-center gap-1">เป้าขนทราย (คิว)
                        <input type="number" min="0" value={roundTargetCubic} onChange={e => setRoundTargetCubic(Number(e.target.value || 0))} className="w-20 rounded border border-slate-200 dark:border-white/20 bg-white dark:bg-white/5 px-2 py-1" />
                    </label>
                    <label className="flex items-center gap-1">เป้าจำนวนวันล้าง
                        <input type="number" min="0" value={roundTargetDays} onChange={e => setRoundTargetDays(Number(e.target.value || 0))} className="w-16 rounded border border-slate-200 dark:border-white/20 bg-white dark:bg-white/5 px-2 py-1" />
                    </label>
                    <label className="flex items-center gap-1">เป้าจำนวนถัง
                        <input type="number" min="0" value={roundTargetDrums} onChange={e => setRoundTargetDrums(Number(e.target.value || 0))} className="w-16 rounded border border-slate-200 dark:border-white/20 bg-white dark:bg-white/5 px-2 py-1" />
                    </label>
                </div>
                <div className="mt-2 text-xs">
                    <label className="flex items-center gap-1 text-slate-600 dark:text-slate-300">ขั้นต่ำก่อนตัดรอบ (วัน)
                        <input type="number" min="1" value={roundCloseMinDays} onChange={e => setRoundCloseMinDays(Math.max(1, Number(e.target.value || 1)))} className="w-16 rounded border border-slate-200 dark:border-white/20 bg-white dark:bg-white/5 px-2 py-1" />
                        <span className="text-slate-500 dark:text-slate-400">รองรับเคสล้าง 2-3 วัน แล้วถังเป็น 0 ค่อยตัดรอบ</span>
                    </label>
                </div>
                <div className="mt-3 rounded-xl border border-cyan-100 dark:border-cyan-500/20 bg-cyan-50/70 dark:bg-cyan-500/10 p-3 transition-all duration-300">
                    <div className="flex flex-wrap items-center gap-2 text-xs font-semibold text-cyan-900 dark:text-cyan-100">
                        <span className="rounded-lg bg-white/80 dark:bg-slate-900/30 px-2 py-1">ขนทราย {sandRoundOverview.transportedCubic.toLocaleString()} / {roundTargetCubic.toLocaleString()} คิว</span>
                        <span className="text-cyan-500">→</span>
                        <span className="rounded-lg bg-white/80 dark:bg-slate-900/30 px-2 py-1">ล้าง {sandRoundOverview.washDays} / {roundTargetDays} วัน ({sandRoundOverview.washedCubic.toLocaleString()} คิว)</span>
                        <span className="text-cyan-500">→</span>
                        <span className="rounded-lg bg-white/80 dark:bg-slate-900/30 px-2 py-1">ได้ {sandRoundOverview.obtainedDrums.toLocaleString()} / {roundTargetDrums.toLocaleString()} ถัง</span>
                        <span className="text-cyan-500">→</span>
                        <span className="rounded-lg bg-white/80 dark:bg-slate-900/30 px-2 py-1">ล้างที่บ้าน {sandRoundOverview.washedHomeDrums.toLocaleString()} ถัง</span>
                    </div>
                    <div className={`mt-3 rounded-lg border px-3 py-2 text-sm font-semibold flex items-center gap-2 transition-all duration-300 ${sandRoundOverview.completed ? 'border-emerald-200 dark:border-emerald-500/30 bg-emerald-50/80 dark:bg-emerald-500/10 text-emerald-800 dark:text-emerald-200' : 'border-amber-200 dark:border-amber-500/30 bg-amber-50/80 dark:bg-amber-500/10 text-amber-800 dark:text-amber-200'}`}>
                        {sandRoundOverview.completed ? <CheckCircle2 className="h-4 w-4" /> : <Timer className="h-4 w-4" />}
                        {sandRoundOverview.completed ? 'สรุปรอบนี้: เสร็จครบตาม Flowchart แล้ว' : `ยังไม่ครบรอบ: เหลือถังที่ต้องล้างที่บ้านอีก ${sandRoundOverview.remainingDrums.toLocaleString()} ถัง`}
                    </div>
                </div>
                <div className="mt-3 rounded-2xl border border-slate-200/70 dark:border-white/10 bg-white/85 dark:bg-slate-900/25 p-3.5 shadow-inner">
                    <h5 className="text-xs font-bold text-slate-700 dark:text-slate-200 mb-2">Flowchart รอบปัจจุบัน</h5>
                    <div className="grid gap-3 lg:grid-cols-3 text-xs">
                        <button type="button" onClick={() => openFlowStepDetail('transport')} className={`group relative overflow-hidden text-left rounded-2xl border bg-white/95 dark:bg-slate-900/55 p-3.5 transition-all duration-300 shadow-sm hover:-translate-y-0.5 hover:shadow-lg ${selectedFlowStep === 'transport' ? 'ring-2 ring-sky-400/70 border-sky-300 dark:border-sky-400/60' : 'border-sky-200/80 dark:border-sky-500/30'}`}>
                            <div className="pointer-events-none absolute -right-8 -top-8 h-20 w-20 rounded-full bg-sky-400/15 blur-xl" />
                            <p className="text-[10px] tracking-wide uppercase text-sky-700/90 dark:text-sky-300/90 flex items-center gap-1"><Sparkles className="h-3.5 w-3.5" /> Step 1 · ขนทรายเข้า</p>
                            <p className="mt-1.5 text-xl font-black text-slate-800 dark:text-slate-100 tabular-nums">{(selectedRound?.transportedCubic || 0).toLocaleString()} <span className="text-sm font-semibold text-slate-500">/ {roundTargetCubic.toLocaleString()} คิว</span></p>
                            <div className="mt-2 h-1.5 rounded-full bg-sky-100 dark:bg-sky-900/40 overflow-hidden">
                                <div className="h-full rounded-full bg-gradient-to-r from-sky-400 to-cyan-500 transition-all duration-700" style={{ width: `${toProgressPercent(selectedRound?.transportedCubic || 0, roundTargetCubic)}%` }} />
                            </div>
                        </button>
                        <button type="button" onClick={() => openFlowStepDetail('wash')} className={`group relative overflow-hidden text-left rounded-2xl border bg-white/95 dark:bg-slate-900/55 p-3.5 transition-all duration-300 shadow-sm hover:-translate-y-0.5 hover:shadow-lg ${selectedFlowStep === 'wash' ? 'ring-2 ring-blue-400/70 border-blue-300 dark:border-blue-400/60' : 'border-blue-200/80 dark:border-blue-500/30'}`}>
                            <div className="pointer-events-none absolute -right-8 -top-8 h-20 w-20 rounded-full bg-blue-400/15 blur-xl" />
                            <p className="text-[10px] tracking-wide uppercase text-blue-700/90 dark:text-blue-300/90">Step 2 · ล้างทราย</p>
                            <p className="mt-1.5 text-xl font-black text-slate-800 dark:text-slate-100 tabular-nums">{(selectedRound?.washDays || 0)} <span className="text-sm font-semibold text-slate-500">/ {roundTargetDays} วัน</span></p>
                            <p className="text-[11px] text-blue-700 dark:text-blue-300 mt-0.5">{(selectedRound?.washedCubic || 0).toLocaleString()} คิว</p>
                            <div className="mt-2 h-1.5 rounded-full bg-blue-100 dark:bg-blue-900/40 overflow-hidden">
                                <div className="h-full rounded-full bg-gradient-to-r from-blue-400 to-indigo-500 transition-all duration-700" style={{ width: `${toProgressPercent(selectedRound?.washDays || 0, roundTargetDays)}%` }} />
                            </div>
                        </button>
                        <button type="button" onClick={() => openFlowStepDetail('obtained')} className={`group relative overflow-hidden text-left rounded-2xl border bg-white/95 dark:bg-slate-900/55 p-3.5 transition-all duration-300 shadow-sm hover:-translate-y-0.5 hover:shadow-lg ${selectedFlowStep === 'obtained' ? 'ring-2 ring-indigo-400/70 border-indigo-300 dark:border-indigo-400/60' : 'border-indigo-200/80 dark:border-indigo-500/30'}`}>
                            <div className="pointer-events-none absolute -right-8 -top-8 h-20 w-20 rounded-full bg-indigo-400/15 blur-xl" />
                            <p className="text-[10px] tracking-wide uppercase text-indigo-700/90 dark:text-indigo-300/90">Step 3 · ได้ถัง</p>
                            <p className="mt-1.5 text-xl font-black text-slate-800 dark:text-slate-100 tabular-nums">{(selectedRound?.obtainedDrums || 0).toLocaleString()} <span className="text-sm font-semibold text-slate-500">/ {roundTargetDrums.toLocaleString()} ถัง</span></p>
                            <div className="mt-2 h-1.5 rounded-full bg-indigo-100 dark:bg-indigo-900/40 overflow-hidden">
                                <div className="h-full rounded-full bg-gradient-to-r from-indigo-400 to-violet-500 transition-all duration-700" style={{ width: `${toProgressPercent(selectedRound?.obtainedDrums || 0, roundTargetDrums)}%` }} />
                            </div>
                        </button>
                    </div>
                    <div className="mt-2 grid gap-2 sm:grid-cols-3 text-xs">
                        <button type="button" onClick={() => openFlowStepDetail('home')} className={`text-left rounded-xl border bg-gradient-to-br from-teal-50 to-white dark:from-teal-500/10 dark:to-slate-900 p-2.5 hover:-translate-y-0.5 transition-all duration-300 shadow-sm ${selectedFlowStep === 'home' ? 'ring-2 ring-teal-400/70 border-teal-300 dark:border-teal-400/60' : 'border-teal-200 dark:border-teal-500/30'}`}>
                            <p className="font-semibold text-teal-800 dark:text-teal-200">4) ล้างที่บ้าน</p>
                            <p className="mt-1 text-slate-700 dark:text-slate-200">{(selectedRound?.washedHomeDrums || 0).toLocaleString()} ถัง</p>
                        </button>
                        <div className="rounded-xl border border-amber-200 dark:border-amber-500/30 bg-gradient-to-br from-amber-50 to-white dark:from-amber-500/10 dark:to-slate-900 p-2.5 hover:-translate-y-0.5 transition-all duration-300 shadow-sm">
                            <p className="font-semibold text-amber-800 dark:text-amber-200">คงเหลือ</p>
                            <p className="mt-1 text-slate-700 dark:text-slate-200">{(selectedRound?.remainingDrums || 0).toLocaleString()} ถัง</p>
                        </div>
                        <div className={`rounded-xl border p-2.5 ${selectedRound?.completed ? 'border-emerald-200 dark:border-emerald-500/30 bg-emerald-50/80 dark:bg-emerald-500/10' : 'border-slate-200 dark:border-white/20 bg-slate-50/80 dark:bg-white/[0.03]'}`}>
                            <p className={`font-semibold ${selectedRound?.completed ? 'text-emerald-800 dark:text-emerald-200' : 'text-slate-700 dark:text-slate-200'}`}>
                                {selectedRound?.completed ? 'ปิดรอบแล้ว' : 'ยังไม่ปิดรอบ'}
                            </p>
                            <p className="mt-1 text-slate-600 dark:text-slate-300">
                                {selectedRound ? `รอบที่ ${selectedRound.roundNo}` : 'ยังไม่มีข้อมูลรอบในช่วงนี้'}
                            </p>
                        </div>
                    </div>
                </div>
                <div className="mt-3">
                    <h5 className="text-xs font-bold text-slate-700 dark:text-slate-200 mb-2">สรุปเป็นรอบๆ (คลิกเพื่อดูรายละเอียด)</h5>
                    <div className="mb-2 rounded-lg border border-rose-200/70 dark:border-rose-500/30 bg-rose-50/60 dark:bg-rose-500/10 p-2">
                        <p className="text-xs font-bold text-rose-800 dark:text-rose-200">Notification Inbox (ยังไม่รับทราบ) {unackedSandOpsInbox.length} รายการ</p>
                        {unackedSandOpsInbox.length === 0 ? (
                            <p className="text-[11px] text-slate-500 dark:text-slate-400 mt-1">ไม่มีแจ้งเตือนคงค้าง</p>
                        ) : (
                            <ul className="mt-1.5 space-y-1 max-h-28 overflow-y-auto">
                                {unackedSandOpsInbox.slice(0, 12).map(item => (
                                    <li key={item.id} className="flex items-start justify-between gap-2 rounded bg-white/80 dark:bg-white/[0.03] px-2 py-1 text-[11px]">
                                        <button type="button" className="text-left text-slate-700 dark:text-slate-200 hover:underline" onClick={() => setSelectedRoundId(item.roundId)}>
                                            {item.text}
                                        </button>
                                        <button type="button" onClick={() => acknowledgeNotification(item.id)} className="shrink-0 rounded border border-rose-200 dark:border-rose-500/30 px-1.5 py-0.5 text-rose-700 dark:text-rose-300">
                                            รับทราบ
                                        </button>
                                    </li>
                                ))}
                            </ul>
                        )}
                    </div>
                    <div className="mb-2 grid grid-cols-2 sm:grid-cols-4 gap-2 text-xs">
                        <div className="rounded-lg border border-slate-200 dark:border-white/15 bg-white/80 dark:bg-white/[0.03] p-2">
                            <p className="text-slate-500">จำนวนรอบ</p>
                            <p className="font-bold text-slate-800 dark:text-slate-100">{sandRoundOverview.rounds.length}</p>
                        </div>
                        <div className="rounded-lg border border-emerald-200 dark:border-emerald-500/30 bg-emerald-50/70 dark:bg-emerald-500/10 p-2">
                            <p className="text-emerald-700 dark:text-emerald-300">รอบปิดแล้ว</p>
                            <p className="font-bold text-emerald-800 dark:text-emerald-200">{sandRoundOverview.rounds.filter(r => r.completed).length}</p>
                        </div>
                        <div className="rounded-lg border border-blue-200 dark:border-blue-500/30 bg-blue-50/70 dark:bg-blue-500/10 p-2">
                            <p className="text-blue-700 dark:text-blue-300">เฉลี่ยวัน/รอบ</p>
                            <p className="font-bold text-blue-800 dark:text-blue-200">
                                {sandRoundOverview.rounds.length > 0 ? (sandRoundOverview.rounds.reduce((s, r) => s + r.washDays, 0) / sandRoundOverview.rounds.length).toFixed(1) : '0.0'}
                            </p>
                        </div>
                        <div className="rounded-lg border border-violet-200 dark:border-violet-500/30 bg-violet-50/70 dark:bg-violet-500/10 p-2">
                            <p className="text-violet-700 dark:text-violet-300">Yield เฉลี่ย (ถัง/คิว)</p>
                            <p className="font-bold text-violet-800 dark:text-violet-200">
                                {sandRoundOverview.rounds.length > 0
                                    ? (sandRoundOverview.rounds.reduce((s, r) => s + (r.washedCubic > 0 ? (r.obtainedDrums / r.washedCubic) : 0), 0) / sandRoundOverview.rounds.length).toFixed(3)
                                    : '0.000'}
                            </p>
                        </div>
                    </div>
                    {sandRoundOverview.rounds.length === 0 ? (
                        <p className="text-xs text-slate-500 dark:text-slate-400">ยังไม่พบกิจกรรมรอบล้างทรายในช่วงวันที่ที่เลือก</p>
                    ) : (
                        <ul className="space-y-2 max-h-64 overflow-y-auto">
                            {sandRoundOverview.rounds.map((r, idx) => (
                                <li key={r.id} className={`rounded-lg border p-2.5 text-xs transition-all duration-300 hover:-translate-y-0.5 hover:shadow-md cursor-pointer ${selectedRoundId === r.id ? 'ring-2 ring-cyan-400/60 dark:ring-cyan-500/50' : ''} ${r.completed ? 'border-emerald-200 dark:border-emerald-500/30 bg-emerald-50/60 dark:bg-emerald-500/10' : 'border-amber-200 dark:border-amber-500/30 bg-amber-50/60 dark:bg-amber-500/10'}`} style={{ animationDelay: `${idx * 80}ms`}} onClick={() => setSelectedRoundId(r.id)}>
                                    <div className="font-semibold text-slate-800 dark:text-slate-100">
                                        รอบที่ {r.roundNo} · {formatDateBE(r.startDate)} - {formatDateBE(r.endDate)} {r.completed ? '· ปิดรอบแล้ว' : '· กำลังดำเนินการ'}
                                    </div>
                                    <p className="mt-1 text-slate-700 dark:text-slate-200">
                                        ขน {r.transportedCubic.toLocaleString()} คิว | ล้าง {r.washDays} วัน ({r.washedCubic.toLocaleString()} คิว) | ได้ {r.obtainedDrums.toLocaleString()} ถัง | ล้างที่บ้าน {r.washedHomeDrums.toLocaleString()} ถัง
                                    </p>
                                    <p className="mt-1 text-slate-600 dark:text-slate-300">
                                        คำนวณรายวัน: {r.days.map(d => `${formatDateBE(d.date)} ล้าง ${d.washed.toLocaleString()} คิว ได้ ${d.obtained.toLocaleString()} ถัง ล้างบ้าน ${d.home.toLocaleString()} ถัง`).join(' | ')}
                                    </p>
                                </li>
                            ))}
                        </ul>
                    )}
                </div>
                {selectedRound && (
                    <div className="mt-3 rounded-xl border border-slate-200 dark:border-white/10 bg-white/90 dark:bg-slate-900/35 p-3">
                        <div className="mb-2 flex flex-wrap gap-2">
                            <Button type="button" variant="outline" className="px-2.5 py-1 text-xs" onClick={exportSelectedRoundCsv}>
                                <FileDown className="h-3.5 w-3.5" /> Export รอบนี้ CSV
                            </Button>
                            <Button type="button" variant="outline" className="px-2.5 py-1 text-xs" onClick={printSelectedRound}>
                                <Printer className="h-3.5 w-3.5" /> พิมพ์/Export PDF รอบนี้
                            </Button>
                            <label className="text-xs text-slate-600 dark:text-slate-300 flex items-center gap-1 rounded-lg border border-slate-200 dark:border-white/15 px-2 py-1">
                                แจ้งเตือนค้างเกิน
                                <input type="number" min="1" value={alertAgingDays} onChange={e => { const v = Math.max(1, Number(e.target.value || 1)); setAlertAgingDays(v); updateNotificationRules(v); }} className="w-14 rounded border border-slate-200 dark:border-white/20 bg-white dark:bg-white/5 px-1.5 py-0.5" />
                                วัน
                            </label>
                            {canManageSandRounds && !selectedRound.completed && (
                                <Button type="button" variant="outline" className="px-2.5 py-1 text-xs text-amber-700 border-amber-300 dark:text-amber-300 dark:border-amber-500/40" onClick={() => closeRoundManually(selectedRound.id)}>
                                    ปิดรอบด้วยสิทธิ์ผู้ดูแล
                                </Button>
                            )}
                        </div>
                        <h5 className="text-xs font-bold text-slate-800 dark:text-slate-100 mb-2">
                            รายละเอียดรอบที่ {selectedRound.roundNo} แบบละเอียด {selectedRound.completionReason ? `· ${selectedRound.completionReason}` : ''}
                        </h5>
                        <div className="mb-2 flex flex-wrap items-center gap-2 text-xs">
                            <span className="text-slate-600 dark:text-slate-300">Workflow:</span>
                            <select
                                value={selectedRoundWorkflowStatus}
                                onChange={e => {
                                    const nextStatus = e.target.value as 'Open' | 'Reviewing' | 'Closed' | 'Reopened';
                                    const reason = workflowReason.trim();
                                    if (nextStatus === 'Closed' && selectedRoundHighUnacked > 0 && !/override/i.test(reason)) {
                                        window.alert(`ยังมีแจ้งเตือนระดับสูงคงค้าง ${selectedRoundHighUnacked} รายการ: หากต้องการปิดรอบให้ใส่เหตุผลที่มีคำว่า "override"`);
                                        return;
                                    }
                                    updateRoundWorkflow(selectedRound.id, nextStatus, reason);
                                }}
                                disabled={!canManageSandRounds}
                                className="rounded border border-slate-200 dark:border-white/20 bg-white dark:bg-white/5 px-2 py-1"
                            >
                                <option value="Open">Open</option>
                                <option value="Reviewing">Reviewing</option>
                                <option value="Closed">Closed</option>
                                <option value="Reopened">Reopened</option>
                            </select>
                            <input
                                value={workflowReason}
                                onChange={e => setWorkflowReason(e.target.value)}
                                placeholder="เหตุผล (บังคับเมื่อ Closed/Reopened)"
                                className="rounded border border-slate-200 dark:border-white/20 bg-white dark:bg-white/5 px-2 py-1"
                            />
                            {sandRoundWorkflowById[selectedRound.id]?.reason && (
                                <span className="text-slate-500 dark:text-slate-400">เหตุผล: {sandRoundWorkflowById[selectedRound.id]?.reason}</span>
                            )}
                        </div>
                        {selectedRoundDelta && (
                            <div className="mb-2 rounded-lg border border-violet-200 dark:border-violet-500/30 bg-violet-50/70 dark:bg-violet-500/10 px-2 py-1.5 text-xs">
                                เทียบรอบก่อนหน้า (รอบ {selectedRoundDelta.prevRoundNo}): วันล้าง {selectedRoundDelta.dayDelta > 0 ? '+' : ''}{selectedRoundDelta.dayDelta} วัน | Yield {selectedRoundDelta.yieldDeltaPct > 0 ? '+' : ''}{selectedRoundDelta.yieldDeltaPct.toFixed(1)}%
                            </div>
                        )}
                        {selectedRoundAutoAlerts.length > 0 && (
                            <div className="mb-2 space-y-1">
                                {selectedRoundAutoAlerts.map(a => (
                                    <div key={a.id} className={`rounded-lg px-2 py-1.5 text-[11px] ${a.severity === 'high' ? 'bg-red-50 text-red-700 border border-red-200 dark:bg-red-500/10 dark:text-red-200 dark:border-red-500/30' : 'bg-amber-50 text-amber-800 border border-amber-200 dark:bg-amber-500/10 dark:text-amber-200 dark:border-amber-500/30'}`}>
                                        {a.text}
                                    </div>
                                ))}
                            </div>
                        )}
                        <div className="grid grid-cols-2 sm:grid-cols-5 gap-2 text-xs">
                            <div className="rounded-lg bg-slate-50 dark:bg-white/[0.04] p-2"><p className="text-slate-500">ช่วงวันที่</p><p className="font-semibold text-slate-800 dark:text-slate-100">{formatDateBE(selectedRound.startDate)} - {formatDateBE(selectedRound.endDate)}</p></div>
                            <div className="rounded-lg bg-sky-50/80 dark:bg-sky-500/10 p-2"><p className="text-slate-500">ขนทรายรวม</p><p className="font-semibold text-slate-800 dark:text-slate-100">{selectedRound.transportedCubic.toLocaleString()} คิว</p></div>
                            <div className="rounded-lg bg-blue-50/80 dark:bg-blue-500/10 p-2"><p className="text-slate-500">ล้างทรายรวม</p><p className="font-semibold text-slate-800 dark:text-slate-100">{selectedRound.washedCubic.toLocaleString()} คิว ({selectedRound.washDays} วัน)</p></div>
                            <div className="rounded-lg bg-indigo-50/80 dark:bg-indigo-500/10 p-2"><p className="text-slate-500">ได้ถังรวม</p><p className="font-semibold text-slate-800 dark:text-slate-100">{selectedRound.obtainedDrums.toLocaleString()} ถัง</p></div>
                            <div className="rounded-lg bg-teal-50/80 dark:bg-teal-500/10 p-2"><p className="text-slate-500">ล้างที่บ้านรวม</p><p className="font-semibold text-slate-800 dark:text-slate-100">{selectedRound.washedHomeDrums.toLocaleString()} ถัง</p></div>
                        </div>
                        <div className="mt-2 rounded-lg border border-slate-200 dark:border-white/15 overflow-hidden">
                            <div className="grid grid-cols-12 bg-slate-100/80 dark:bg-white/[0.06] px-2 py-1.5 text-[11px] font-semibold text-slate-600 dark:text-slate-300">
                                <div className="col-span-2">วันที่</div>
                                <div className="col-span-2 text-right">ขนทราย</div>
                                <div className="col-span-2 text-right">ล้างทราย</div>
                                <div className="col-span-2 text-right">ได้ถัง</div>
                                <div className="col-span-2 text-right">ล้างที่บ้าน</div>
                                <div className="col-span-2 text-right">คงเหลือสะสม</div>
                            </div>
                            <div className="max-h-56 overflow-y-auto divide-y divide-slate-100 dark:divide-white/10">
                                {(() => {
                                    let remain = 0;
                                    return selectedRound.days.map((d, i) => {
                                        remain = Math.max(0, remain + d.obtained - d.home);
                                        return (
                                            <div key={`${selectedRound.id}_${d.date}_${i}`} className="grid grid-cols-12 px-2 py-1.5 text-[11px] text-slate-700 dark:text-slate-200 hover:bg-slate-50/80 dark:hover:bg-white/[0.03] transition-colors">
                                                <div className="col-span-2">{formatDateBE(d.date)}</div>
                                                <div className="col-span-2 text-right">{d.transported.toLocaleString()}</div>
                                                <div className="col-span-2 text-right">{d.washed.toLocaleString()}</div>
                                                <div className="col-span-2 text-right">{d.obtained.toLocaleString()}</div>
                                                <div className="col-span-2 text-right">{d.home.toLocaleString()}</div>
                                                <div className="col-span-2 text-right font-semibold">{remain.toLocaleString()}</div>
                                            </div>
                                        );
                                    });
                                })()}
                            </div>
                        </div>
                        <div className="mt-3 rounded-lg border border-violet-200/70 dark:border-violet-500/30 overflow-hidden">
                            <div className="px-2 py-1.5 bg-violet-50/80 dark:bg-violet-500/10 text-[11px] font-semibold text-violet-800 dark:text-violet-200">
                                Timeline มุมมองเดียวจบ (ขน → ล้าง → ได้ถัง → ล้างที่บ้าน)
                            </div>
                            <div className="max-h-44 overflow-y-auto p-2 space-y-2">
                                {roundTimeline.length === 0 ? (
                                    <p className="text-[11px] text-slate-500 dark:text-slate-400">ยังไม่มี timeline ในรอบนี้</p>
                                ) : (
                                    roundTimeline.map(t => (
                                        <div key={`${selectedRound.id}_timeline_${t.date}`} className="relative pl-4">
                                            <span className="absolute left-0 top-1.5 h-2 w-2 rounded-full bg-violet-500" />
                                            <p className="text-[11px] font-semibold text-slate-700 dark:text-slate-200">{formatDateBE(t.date)}</p>
                                            <p className="text-[11px] text-slate-600 dark:text-slate-300">{t.tags.join(' | ')}</p>
                                        </div>
                                    ))
                                )}
                            </div>
                        </div>
                        <div className="mt-3 rounded-lg border border-cyan-200/70 dark:border-cyan-500/30 overflow-hidden">
                            <div className="px-2 py-1.5 bg-cyan-50/80 dark:bg-cyan-500/10 text-[11px] font-semibold text-cyan-800 dark:text-cyan-200">
                                ติดตามย้อนกลับ Lot/Batch ID: ถังล้างที่บ้านมาจากวันล้างไหน และขนมาเมื่อไหร่
                            </div>
                            {canManageSandRounds && (
                                <div className="px-2 py-1.5 border-b border-cyan-100 dark:border-cyan-500/20 bg-white/70 dark:bg-slate-900/20 flex flex-wrap items-center gap-1.5 text-[11px]">
                                    <span className="text-slate-600 dark:text-slate-300">Merge lot:</span>
                                    <input value={mergeSourceBatchId} onChange={e => setMergeSourceBatchId(e.target.value)} placeholder="from batch" className="rounded border border-cyan-200 dark:border-cyan-500/30 bg-white dark:bg-white/5 px-1.5 py-0.5" />
                                    <span className="text-slate-400">→</span>
                                    <input value={mergeTargetBatchId} onChange={e => setMergeTargetBatchId(e.target.value)} placeholder="to batch" className="rounded border border-cyan-200 dark:border-cyan-500/30 bg-white dark:bg-white/5 px-1.5 py-0.5" />
                                    <button type="button" onClick={mergeBatchInRound} disabled={isBatchImmutable} className="rounded border border-cyan-300 px-1.5 py-0.5 text-cyan-700 disabled:opacity-50 dark:text-cyan-300">
                                        merge
                                    </button>
                                </div>
                            )}
                            {selectedRoundTraceRows.length === 0 ? (
                                <p className="px-2 py-2 text-[11px] text-slate-500 dark:text-slate-400">
                                    ยังไม่มีข้อมูลการล้างที่บ้านในรอบนี้ หรือยังจับคู่แหล่งที่มาของถังไม่ได้
                                </p>
                            ) : (
                                <div className="max-h-56 overflow-y-auto divide-y divide-cyan-100 dark:divide-cyan-500/20">
                                    {selectedRoundTraceRows.map((row, idx) => (
                                        <div key={`${selectedRound.id}_trace_${idx}`} className="grid grid-cols-12 gap-1 px-2 py-1.5 text-[11px] text-slate-700 dark:text-slate-200 hover:bg-cyan-50/50 dark:hover:bg-cyan-500/5 transition-colors">
                                            <div className="col-span-3">
                                                <p className="text-slate-500">ล้างที่บ้าน</p>
                                                <p className="font-semibold">{formatDateBE(row.homeDate)}</p>
                                            </div>
                                            <div className="col-span-3">
                                                <p className="text-slate-500">ทรายจากล้าง</p>
                                                <p className="font-semibold">{formatDateBE(row.sourceDate)}</p>
                                            </div>
                                            <div className="col-span-4">
                                                <p className="text-slate-500">ขนเข้า (อ้างอิง)</p>
                                                <p className="font-semibold">{row.linkedTransportDate ? formatDateBE(row.linkedTransportDate) : '-'}</p>
                                            </div>
                                            <div className="col-span-2">
                                                <p className="text-slate-500">Batch ID</p>
                                                {canManageSandRounds ? (
                                                    <div className="space-y-1">
                                                        <input
                                                            type="text"
                                                            value={batchEditDrafts[row.id || `${row.homeDate}_${row.sourceDate}_${idx}`] ?? row.batchId}
                                                            onChange={e => setBatchEditDrafts(prev => ({ ...prev, [row.id || `${row.homeDate}_${row.sourceDate}_${idx}`]: e.target.value }))}
                                                            disabled={isBatchImmutable}
                                                            className="w-full rounded border border-cyan-200 dark:border-cyan-500/30 bg-white dark:bg-slate-900/30 px-1.5 py-0.5 text-[11px]"
                                                        />
                                                        <div className="flex gap-1">
                                                            <button
                                                                type="button"
                                                                disabled={isBatchImmutable}
                                                                onClick={() => {
                                                                    const key = row.id || `${row.homeDate}_${row.sourceDate}_${idx}`;
                                                                    const nextVal = (batchEditDrafts[key] ?? row.batchId).trim();
                                                                    if (!nextVal) return;
                                                                    updateBatchId({ ...row, batchId: nextVal });
                                                                }}
                                                                className="rounded border border-cyan-300 px-1.5 py-0.5 text-[10px] text-cyan-700 disabled:opacity-50 dark:text-cyan-300"
                                                            >
                                                                save
                                                            </button>
                                                            <button
                                                                type="button"
                                                                disabled={isBatchImmutable}
                                                                onClick={() => deleteBatchAllocation(row.id)}
                                                                className="rounded border border-rose-300 px-1.5 py-0.5 text-[10px] text-rose-700 disabled:opacity-50 dark:text-rose-300"
                                                            >
                                                                delete
                                                            </button>
                                                        </div>
                                                    </div>
                                                ) : (
                                                    <p className="font-semibold">{row.batchId}</p>
                                                )}
                                            </div>
                                            <div className="col-span-2 text-right">
                                                <p className="text-slate-500">จำนวนถัง</p>
                                                <p className="font-bold text-cyan-700 dark:text-cyan-300">{row.drums.toLocaleString()}</p>
                                            </div>
                                        </div>
                                    ))}
                                </div>
                            )}
                        </div>
                        {isBatchImmutable && (
                            <p className="mt-1 text-[11px] text-amber-700 dark:text-amber-300">ล็อตถูกล็อกแล้วเพราะสถานะรอบเป็น Closed (แก้ไขได้เมื่อเปลี่ยนเป็น Reopened)</p>
                        )}
                        <div className="mt-3 rounded-lg border border-slate-200 dark:border-white/10 p-2">
                            <h6 className="text-[11px] font-semibold text-slate-700 dark:text-slate-200 mb-1">Audit Trail รอบล้างทราย</h6>
                            <div className="max-h-28 overflow-y-auto space-y-1">
                                {sandRoundAuditTrail.filter(a => a.roundId === selectedRound.id).length === 0 ? (
                                    <p className="text-[11px] text-slate-500 dark:text-slate-400">ยังไม่มีประวัติการแก้ไข/ปิดรอบ</p>
                                ) : (
                                    sandRoundAuditTrail
                                        .filter(a => a.roundId === selectedRound.id)
                                        .slice(0, 20)
                                        .map(a => (
                                            <p key={a.id} className="text-[11px] text-slate-600 dark:text-slate-300">
                                                {a.createdAt} · {a.adminName || '-'} · {a.action} {a.note ? `· ${a.note}` : ''}
                                            </p>
                                        ))
                                )}
                            </div>
                        </div>
                    </div>
                )}
            </Card>
            {isFlowStepModalOpen && selectedFlowStepDetail && (
                <div
                    className="fixed inset-0 z-[120] bg-slate-900/45 backdrop-blur-[1px] flex items-center justify-center p-4"
                    onClick={() => setIsFlowStepModalOpen(false)}
                >
                    <div
                        className="w-full max-w-lg rounded-2xl border border-cyan-200/70 dark:border-cyan-500/30 bg-white dark:bg-slate-900 p-4 shadow-2xl"
                        onClick={(e) => e.stopPropagation()}
                    >
                        <div className="flex items-start justify-between gap-2">
                            <div>
                                <p className="text-sm font-bold text-cyan-900 dark:text-cyan-100">{selectedFlowStepDetail.title}</p>
                                <p className="text-xs text-cyan-700 dark:text-cyan-200 mt-0.5">{selectedFlowStepDetail.subtitle}</p>
                            </div>
                            <button
                                type="button"
                                onClick={() => setIsFlowStepModalOpen(false)}
                                className="rounded-lg border border-slate-200 dark:border-white/20 px-2 py-1 text-xs text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-white/10"
                            >
                                ปิด
                            </button>
                        </div>
                        <ul className="mt-3 space-y-1.5 max-h-80 overflow-y-auto">
                            {selectedFlowStepDetail.rows.length === 0 ? (
                                <li className="text-xs text-slate-500 dark:text-slate-400">ไม่มีข้อมูลในขั้นนี้ของรอบที่เลือก</li>
                            ) : (
                                selectedFlowStepDetail.rows.map((row, idx) => (
                                    <li key={`flow_step_modal_${idx}`} className="text-xs text-slate-700 dark:text-slate-200 rounded-lg bg-slate-50 dark:bg-white/[0.03] px-2.5 py-2">
                                        {row}
                                    </li>
                                ))
                            )}
                        </ul>
                    </div>
                </div>
            )}

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
                                แดง = ไม่มีบันทึก, ส้ม = ซ้ำแบบตรงกัน, เหลือง = ซ้ำใกล้เคียง, เขียว = ปกติ
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
                                    <button type="button" onClick={openDailyWizard} key={cell.date} title={`พบข้อมูลซ้ำแบบตรงกัน: ${formatDateBE(cell.date)}`} className={`${base} text-orange-700 dark:text-orange-200 bg-orange-100 dark:bg-orange-500/20 ${sundayClass} ${holidayClass}${dim}`}>
                                        {cell.day}
                                    </button>
                                );
                            }
                            if (cell.nearDuplicate) {
                                return (
                                    <button type="button" onClick={openDailyWizard} key={cell.date} title={`พบข้อมูลซ้ำใกล้เคียง: ${formatDateBE(cell.date)}`} className={`${base} text-amber-700 dark:text-amber-200 bg-amber-100 dark:bg-amber-500/20 ${sundayClass} ${holidayClass}${dim}`}>
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
                        รวมวันไม่มีบันทึก {dayAnalysis.emptyDays.length} วัน | ซ้ำแบบตรงกัน {exactDuplicateDaySet.size} วัน | ซ้ำใกล้เคียง {nearDuplicateDaySet.size} วัน
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
                            const fixGuide = buildExactDuplicateFixGuide(items);
                            return (
                                <li key={key} className="rounded-xl border border-orange-200 dark:border-orange-500/30 bg-orange-50/50 dark:bg-orange-500/10 p-3 text-sm">
                                    <div className="font-semibold text-slate-800 dark:text-slate-100">
                                        [{formatDateBE(normalizeDate(sample.date))}] {sample.category}
                                        {sample.subCategory ? ` / ${sample.subCategory}` : ''} · {Number(sample.amount).toLocaleString()} บาท
                                    </div>
                                    <p className="text-xs text-slate-600 dark:text-slate-400 mt-1 line-clamp-2">{sample.description || '(ไม่มีรายละเอียด)'}</p>
                                    <p className="text-xs font-bold text-orange-800 dark:text-orange-200 mt-2">ซ้ำแบบตรงกัน พบ {items.length} รายการ</p>
                                    <div className="mt-2 rounded-lg border border-orange-200/80 bg-white/80 px-2.5 py-2 text-xs text-slate-700 dark:border-orange-500/30 dark:bg-slate-900/30 dark:text-slate-200">
                                        <p><span className="font-semibold">สาเหตุ:</span> {fixGuide.why}</p>
                                        <p className="mt-1"><span className="font-semibold">สิ่งที่ควรแก้:</span> {fixGuide.howToFix}</p>
                                        <p className="mt-1 break-all text-[11px] text-slate-500 dark:text-slate-400"><span className="font-semibold">รหัสรายการ:</span> {fixGuide.ids}</p>
                                    </div>
                                    <Button type="button" variant="outline" className="mt-2 px-2.5 py-1 text-xs" onClick={() => onGoToDailyWizard?.(normalizeDate(sample.date), getStepByCategory(sample.category, sample.subCategory))}>ไปแก้ใน Daily Wizard</Button>
                                </li>
                            );
                        })}
                        {nearDuplicateFindings.map(f => (
                            <li key={f.id} className="rounded-xl border border-amber-200 dark:border-amber-500/30 bg-amber-50/40 dark:bg-amber-500/10 p-3 text-sm">
                                <div className="font-semibold text-slate-800 dark:text-slate-100">[{formatDateBE(f.date)}] {f.category}{f.subCategory ? ` / ${f.subCategory}` : ''}</div>
                                <p className="text-xs text-slate-600 dark:text-slate-400 mt-1">{f.reason} · {Number(f.amountA).toLocaleString()} vs {Number(f.amountB).toLocaleString()} บาท</p>
                                <p className="text-xs text-slate-500 dark:text-slate-400 mt-1">"{f.descA || '-'}" ↔ "{f.descB || '-'}"</p>
                                <div className="mt-2 rounded-lg border border-amber-200/80 bg-white/80 px-2.5 py-2 text-xs text-slate-700 dark:border-amber-500/30 dark:bg-slate-900/30 dark:text-slate-200">
                                    <p><span className="font-semibold">สาเหตุ:</span> ระบบมองว่าข้อมูล 2 รายการนี้ใกล้เคียงกันผิดปกติ ({f.reason})</p>
                                    <p className="mt-1"><span className="font-semibold">สิ่งที่ควรแก้:</span> {buildNearDuplicateFixGuide(f.reason)}</p>
                                </div>
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
