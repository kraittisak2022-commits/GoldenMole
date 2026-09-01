import { useMemo, useState, Fragment } from 'react';
import { FileDown, Fuel, Printer, Truck } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Select from '../../components/ui/Select';
import type { AppSettings, Employee, Transaction } from '../../types';
import {
    THAI_MONTHS,
    computeFuelStockBalances,
    daysInMonth,
    formatDateBE,
    formatDisplayNumber,
    getToday,
    normalizeDate,
    ymdFromParts,
} from '../../utils';
import { estimateSieveUsageByDay } from '../../utils/fuelSieveEstimate';
import {
    buildFuelUsageReport,
    filterFuelUsageReport,
    fuelPrintGroupTitle,
    fuelPrintOverviewSections,
    fuelUsageToCsv,
    fuelUsageToPrintHtml,
    monthBoundsFromYmd,
    shiftMonthBounds,
    yearBoundsFromYmd,
    type FuelPrintGroup,
    type FuelPrintLocale,
    type FuelTypeFilter,
    type FuelUsageKind,
} from '../../utils/fuelUsageReport';
import {
    buildVehicleUsageReport,
    filterVehicleUsageByVehicle,
    filterVehicleUsageReport,
    vehicleKindLabel,
    vehiclePrintGroupTitle,
    vehicleUsageToCsv,
    vehicleUsageToPrintHtml,
    type VehiclePrintGroup,
    type VehicleUsageKind,
} from '../../utils/vehicleUsageReport';
import { transactionVehicleLabel } from '../../utils/vehicleCatalog';

const PRINT_GROUPS: FuelPrintGroup[] = ['overview', 'stock_in', 'macro', 'sieve_generator', 'other_fill'];

type ReportMenu = 'fuel' | 'vehicle';

const VEHICLE_REPORT_TABS: Array<{ id: VehicleUsageKind; label: string; printGroup: Exclude<VehiclePrintGroup, 'overview'> }> = [
    { id: 'macro', label: 'รายงานรถแม็คโคร', printGroup: 'macro' },
    { id: 'dump_trip', label: 'รายงานรถดั๊ม / สิบล้อ / ดรัม', printGroup: 'dump' },
    { id: 'hire', label: 'รายงานการใช้รถ (ค่าจ้าง)', printGroup: 'hire' },
];

interface ReportsModuleProps {
    transactions: Transaction[];
    settings: AppSettings;
    employees?: Employee[];
    /** คงไว้เพื่อความเข้ากันได้กับ App — รายงานนี้ไม่แสดงยอดเงิน */
    maskAmounts?: boolean;
}

const KIND_OPTIONS: Array<{ id: '' | FuelUsageKind; label: string }> = [
    { id: '', label: 'ทุกรายการ' },
    { id: 'stock_in', label: 'รับเข้า (ถังหลัก)' },
    { id: 'withdraw', label: 'เบิกไปถังสำรอง' },
    { id: 'vehicle', label: 'ใช้แล้ว (รถ/แม็คโคร)' },
    { id: 'sand_sieve', label: 'ใช้แล้ว (ร่อนทราย)' },
    { id: 'other_out', label: 'ใช้แล้ว (อื่น ๆ)' },
];

const selectClass = 'dark:bg-white/5 dark:text-slate-100 dark:border-white/20';

function parseYmd(ymd: string): { year: number; month: number; day: number } {
    const [y, m, d] = normalizeDate(ymd).split('-').map(Number);
    return { year: y || 2026, month: m || 1, day: d || 1 };
}

/** ตัวเลือกวัน / เดือน (ชื่อไทย) / ปี พ.ศ. → ค่า YYYY-MM-DD */
const ThaiDateSelect = ({
    label,
    value,
    onChange,
}: {
    label: string;
    value: string;
    onChange: (ymd: string) => void;
}) => {
    const { year, month, day } = parseYmd(value);
    const maxDay = daysInMonth(year, month);
    const beYear = year + 543;
    const yearOptions = useMemo(() => {
        const currentBe = new Date().getFullYear() + 543;
        const years: number[] = [];
        for (let y = currentBe + 1; y >= currentBe - 12; y -= 1) years.push(y);
        if (!years.includes(beYear)) years.push(beYear);
        return years.sort((a, b) => b - a);
    }, [beYear]);

    const setPart = (next: { year?: number; month?: number; day?: number }) => {
        onChange(ymdFromParts(next.year ?? year, next.month ?? month, next.day ?? day));
    };

    return (
        <fieldset className="w-full min-w-0">
            <legend className="text-xs font-bold text-slate-500 dark:text-slate-400 uppercase tracking-wider mb-1.5">{label}</legend>
            <div className="grid grid-cols-3 gap-2">
                <Select
                    aria-label={`${label} วัน`}
                    value={String(Math.min(day, maxDay))}
                    onChange={e => setPart({ day: Number(e.target.value) })}
                    className={selectClass}
                >
                    {Array.from({ length: maxDay }, (_, i) => i + 1).map(d => (
                        <option key={d} value={d}>{d}</option>
                    ))}
                </Select>
                <Select
                    aria-label={`${label} เดือน`}
                    value={String(month)}
                    onChange={e => setPart({ month: Number(e.target.value) })}
                    className={selectClass}
                >
                    {THAI_MONTHS.map((name, i) => (
                        <option key={name} value={i + 1}>{name}</option>
                    ))}
                </Select>
                <Select
                    aria-label={`${label} ปี`}
                    value={String(beYear)}
                    onChange={e => setPart({ year: Number(e.target.value) - 543 })}
                    className={selectClass}
                >
                    {yearOptions.map(y => (
                        <option key={y} value={y}>{y}</option>
                    ))}
                </Select>
            </div>
        </fieldset>
    );
};

const SummaryTile = ({
    label,
    value,
    hint,
}: {
    label: string;
    value: string;
    hint?: string;
}) => (
    <div className="rounded-xl border border-slate-200/90 dark:border-white/10 bg-white dark:bg-white/[0.03] px-3.5 py-3">
        <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">{label}</p>
        <p className="mt-1 text-xl font-bold tabular-nums tracking-tight text-slate-900 dark:text-slate-50">{value}</p>
        {hint ? <p className="text-[11px] text-slate-500 dark:text-slate-400 mt-1">{hint}</p> : null}
    </div>
);

const ReportsModule = ({ transactions, settings, employees = [] }: ReportsModuleProps) => {
    const today = getToday();
    const initial = monthBoundsFromYmd(today);
    const [menu, setMenu] = useState<ReportMenu>('fuel');
    const [start, setStart] = useState(initial.start);
    const [end, setEnd] = useState(initial.end);
    const [vehicleId, setVehicleId] = useState('');
    const [fuelType, setFuelType] = useState<'' | FuelTypeFilter>('');
    const [kind, setKind] = useState<'' | FuelUsageKind>('');
    const [vehicleKind, setVehicleKind] = useState<VehicleUsageKind>('macro');

    const orgTitle = (settings.orgProfile?.name || settings.appName || 'Goldenmole').trim();
    const orgLine = [settings.orgProfile?.address, settings.orgProfile?.phone].filter(Boolean).join(' · ');

    const fuelVehicleOptions = useMemo(() => {
        const catalog = settings.vehicleCatalog || [];
        const names = new Set<string>(settings.cars || []);
        transactions.forEach((t) => {
            if (t.category !== 'Fuel') return;
            const label = transactionVehicleLabel(
                { vehicleId: t.vehicleId, vehicleName: t.vehicleName },
                catalog,
            );
            if (label) names.add(label);
        });
        return Array.from(names).sort((a, b) => a.localeCompare(b, 'th'));
    }, [settings.cars, settings.vehicleCatalog, transactions]);

    const range = useMemo(() => {
        const a = normalizeDate(start);
        const b = normalizeDate(end);
        return a <= b ? { start: a, end: b } : { start: b, end: a };
    }, [start, end]);

    const estimatedSieveByDay = useMemo(
        () => estimateSieveUsageByDay(transactions),
        [transactions]
    );

    const fuelReport = useMemo(
        () => buildFuelUsageReport(transactions, {
            start: range.start,
            end: range.end,
            vehicleId,
            fuelType,
            kind,
            estimatedSieveByDay,
            vehicleCatalog: settings.vehicleCatalog,
        }),
        [transactions, range.start, range.end, vehicleId, fuelType, kind, estimatedSieveByDay, settings.vehicleCatalog]
    );

    const vehicleReport = useMemo(
        () => buildVehicleUsageReport(transactions, employees, {
            start: range.start,
            end: range.end,
            vehicleId,
            kind: vehicleKind,
            vehicleCatalog: settings.vehicleCatalog,
        }),
        [transactions, employees, range.start, range.end, vehicleId, vehicleKind, settings.vehicleCatalog]
    );

    const opsVehicleOptions = useMemo(() => {
        const unfiltered = buildVehicleUsageReport(transactions, employees, {
            start: range.start,
            end: range.end,
            kind: vehicleKind,
            vehicleCatalog: settings.vehicleCatalog,
        });
        return unfiltered.byVehicle
            .map((row) => row.vehicleId)
            .filter(Boolean)
            .sort((a, b) => a.localeCompare(b, 'th'));
    }, [transactions, employees, range.start, range.end, vehicleKind, settings.vehicleCatalog]);

    const remainingStock = useMemo(() => {
        const throughEnd = transactions.filter(t => normalizeDate(t.date) <= range.end);
        const sieveThroughEnd: Record<string, number> = {};
        for (const [day, liters] of Object.entries(estimatedSieveByDay)) {
            if (normalizeDate(day) <= range.end) sieveThroughEnd[day] = liters;
        }
        return computeFuelStockBalances(throughEnd, {
            ...settings.fuelOpeningStockLiters,
            estimatedSieveByDay: sieveThroughEnd,
            asOfYmd: range.end,
        });
    }, [transactions, range.end, settings.fuelOpeningStockLiters, estimatedSieveByDay]);

    const liters = (n: number) => `${formatDisplayNumber(n)} ลิตร`;
    const rangeLabel = `${formatDateBE(range.start)} – ${formatDateBE(range.end)}`;

    const overviewSections = useMemo(() => fuelPrintOverviewSections(fuelReport), [fuelReport]);

    const activeVehicleTab = VEHICLE_REPORT_TABS.find((t) => t.id === vehicleKind) || VEHICLE_REPORT_TABS[0];
    const vehiclePrintGroup = activeVehicleTab.printGroup;

    const applyBounds = (bounds: { start: string; end: string }) => {
        setStart(bounds.start);
        setEnd(bounds.end);
    };

    const exportFuelCsv = () => {
        const csv = fuelUsageToCsv(
            fuelReport,
            {
                start: range.start,
                end: range.end,
                vehicleId,
                fuelType,
                kind,
                estimatedSieveByDay,
            },
            remainingStock
        );
        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `fuel-usage-${range.start}-to-${range.end}.csv`;
        a.click();
        URL.revokeObjectURL(url);
    };

    const exportVehicleCsv = () => {
        const csv = vehicleUsageToCsv(vehicleReport, {
            start: range.start,
            end: range.end,
            vehicleId,
            kind: vehicleKind,
        });
        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `vehicle-usage-${range.start}-to-${range.end}.csv`;
        a.click();
        URL.revokeObjectURL(url);
    };

    const printFuelGroupReport = (group: FuelPrintGroup, locale: FuelPrintLocale = 'th') => {
        const grouped = group === 'overview'
            ? fuelReport
            : filterFuelUsageReport(fuelReport, group);
        const html = fuelUsageToPrintHtml({
            appName: orgTitle,
            orgSubtitle: orgLine || undefined,
            rangeLabel,
            report: grouped,
            group,
            fullReport: fuelReport,
            formatDate: formatDateBE,
            locale,
        });
        const w = window.open('', '_blank');
        if (!w) return;
        w.document.open();
        w.document.write(html);
        w.document.close();
        w.focus();
        w.print();
    };

    const printVehicleGroupReport = (
        group: VehiclePrintGroup,
        locale: 'th' | 'zh' = 'th',
        opts?: { vehicleId?: string },
    ) => {
        let grouped = group === 'overview'
            ? vehicleReport
            : filterVehicleUsageReport(vehicleReport, group);
        if (opts?.vehicleId) {
            grouped = filterVehicleUsageByVehicle(grouped, opts.vehicleId);
        }
        const html = vehicleUsageToPrintHtml({
            appName: orgTitle,
            orgSubtitle: orgLine || undefined,
            rangeLabel,
            report: grouped,
            group,
            formatDate: formatDateBE,
            locale,
            vehicleTitle: opts?.vehicleId,
        });
        const w = window.open('', '_blank');
        if (!w) return;
        w.document.open();
        w.document.write(html);
        w.document.close();
        w.focus();
        w.print();
    };

    const switchMenu = (next: ReportMenu) => {
        setMenu(next);
        setVehicleId('');
        setKind('');
        setVehicleKind('macro');
        setFuelType('');
    };

    const switchVehicleReport = (next: VehicleUsageKind) => {
        setVehicleKind(next);
        setVehicleId('');
    };

    return (
        <div className="space-y-5 print:space-y-4">
            <div className="flex flex-wrap gap-2 print:hidden" role="tablist" aria-label="เมนูย่อยรายงาน">
                <button
                    type="button"
                    role="tab"
                    aria-selected={menu === 'fuel'}
                    onClick={() => switchMenu('fuel')}
                    className={`inline-flex items-center gap-2 rounded-xl px-3.5 py-2 text-sm font-bold transition ${
                        menu === 'fuel'
                            ? 'bg-amber-500 text-white shadow-sm'
                            : 'bg-white text-slate-700 ring-1 ring-slate-200 hover:bg-slate-50 dark:bg-white/5 dark:text-slate-200 dark:ring-white/15'
                    }`}
                >
                    <Fuel size={16} />
                    รายงานการใช้น้ำมัน
                </button>
                <button
                    type="button"
                    role="tab"
                    aria-selected={menu === 'vehicle'}
                    onClick={() => switchMenu('vehicle')}
                    className={`inline-flex items-center gap-2 rounded-xl px-3.5 py-2 text-sm font-bold transition ${
                        menu === 'vehicle'
                            ? 'bg-sky-600 text-white shadow-sm'
                            : 'bg-white text-slate-700 ring-1 ring-slate-200 hover:bg-slate-50 dark:bg-white/5 dark:text-slate-200 dark:ring-white/15'
                    }`}
                >
                    <Truck size={16} />
                    รายงานการใช้รถ
                </button>
            </div>

            {menu === 'fuel' ? (
                <>
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between print:hidden">
                        <div className="min-w-0">
                            <p className="text-xs font-semibold uppercase tracking-[0.12em] text-slate-500 dark:text-slate-400">เอกสารรายงาน</p>
                            <h3 className="mt-1 text-xl font-bold tracking-tight text-slate-900 dark:text-slate-50 flex items-center gap-2">
                                <Fuel className="h-5 w-5 text-slate-700 dark:text-slate-200 shrink-0" />
                                รายงานการใช้น้ำมัน
                            </h3>
                            <p className="mt-1 text-sm text-slate-600 dark:text-slate-400 max-w-2xl">
                                รับเข้า = เพิ่มเข้าถังหลัก · เบิกไปถังสำรองยังไม่นับเป็นใช้ · ใช้แล้ว = รถ/แม็คโคร, รถยนต์, เครื่องปั่นไฟ, อื่นระบุ, ร่อนทราย
                            </p>
                        </div>
                        <div className="flex flex-wrap gap-2 shrink-0">
                            <Button type="button" variant="outline" className="px-3" onClick={exportFuelCsv}>
                                <FileDown className="h-4 w-4" /> Export CSV
                            </Button>
                            {PRINT_GROUPS.map(group => (
                                <Button
                                    key={group}
                                    type="button"
                                    variant="outline"
                                    className="px-3 text-xs sm:text-sm"
                                    aria-label={fuelPrintGroupTitle(group)}
                                    onClick={() => printFuelGroupReport(group)}
                                >
                                    <Printer className="h-4 w-4 shrink-0" />
                                    <span className="max-w-[9rem] truncate sm:max-w-none">{fuelPrintGroupTitle(group)}</span>
                                </Button>
                            ))}
                        </div>
                    </div>

                    <Card className="p-0 overflow-hidden border-slate-200/80 dark:border-white/10 shadow-sm">
                        <div className="border-b border-slate-200 dark:border-white/10 bg-slate-50/80 dark:bg-white/[0.03] px-5 py-4">
                            <p className="text-sm font-semibold text-slate-800 dark:text-slate-100">{orgTitle}</p>
                            {orgLine ? <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">{orgLine}</p> : null}
                            <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
                                ช่วง <span className="font-medium text-slate-800 dark:text-slate-100">{rangeLabel}</span>
                                <span className="text-slate-400 mx-1.5">·</span>
                                {fuelReport.totals.count} รายการ
                            </p>
                        </div>

                        <div className="p-4 sm:p-5 space-y-4 print:hidden">
                            <div className="grid gap-4 lg:grid-cols-2">
                                <ThaiDateSelect label="ตั้งแต่" value={start} onChange={setStart} />
                                <ThaiDateSelect label="ถึง" value={end} onChange={setEnd} />
                            </div>
                            <div className="grid gap-3 sm:grid-cols-3">
                                <Select label="รถ" value={vehicleId} onChange={e => setVehicleId(e.target.value)} className={selectClass}>
                                    <option value="">ทุกคัน</option>
                                    {fuelVehicleOptions.map(name => (
                                        <option key={name} value={name}>{name}</option>
                                    ))}
                                </Select>
                                <Select label="ประเภทน้ำมัน" value={fuelType} onChange={e => setFuelType(e.target.value as '' | FuelTypeFilter)} className={selectClass}>
                                    <option value="">ทุกประเภท</option>
                                    <option value="Diesel">ดีเซล</option>
                                    <option value="Benzine">เบนซิน</option>
                                </Select>
                                <Select label="ประเภทการเคลื่อนไหว" value={kind} onChange={e => setKind(e.target.value as '' | FuelUsageKind)} className={selectClass}>
                                    {KIND_OPTIONS.map(opt => (
                                        <option key={opt.id || 'all'} value={opt.id}>{opt.label}</option>
                                    ))}
                                </Select>
                            </div>
                            <div className="flex flex-wrap gap-2">
                                <Button type="button" variant="ghost" className="px-3 py-2 text-xs" onClick={() => applyBounds(monthBoundsFromYmd(today))}>เดือนนี้</Button>
                                <Button type="button" variant="ghost" className="px-3 py-2 text-xs" onClick={() => applyBounds(shiftMonthBounds(today, -1))}>เดือนที่แล้ว</Button>
                                <Button type="button" variant="ghost" className="px-3 py-2 text-xs" onClick={() => applyBounds(yearBoundsFromYmd(today))}>ปีนี้</Button>
                            </div>
                        </div>
                    </Card>

                    <Card className="p-0 overflow-hidden border-slate-200/80 dark:border-white/10 print:hidden">
                        <div className="px-4 py-3 border-b border-slate-200 dark:border-white/10">
                            <h4 className="text-sm font-bold tracking-wide text-slate-800 dark:text-slate-100 uppercase">สรุปภาพรวมแต่ละรายงาน</h4>
                        </div>
                        <div className="overflow-x-auto">
                            <table className="w-full text-sm">
                                <thead>
                                    <tr className="text-left text-[11px] uppercase tracking-wide text-slate-500 border-b border-slate-100 dark:border-white/10">
                                        <th scope="col" className="px-4 py-2.5 font-semibold">รายงาน</th>
                                        <th scope="col" className="px-4 py-2.5 font-semibold text-right">ลิตร</th>
                                        <th scope="col" className="px-4 py-2.5 font-semibold text-right">รายการ</th>
                                        <th scope="col" className="px-4 py-2.5 font-semibold text-right w-20">พิมพ์</th>
                                        <th scope="col" className="px-4 py-2.5 font-semibold text-right w-28">พิมพ์+ภาษาจีน</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {overviewSections.map((section) => (
                                        <Fragment key={section.id}>
                                            <tr className="bg-slate-100/90 dark:bg-white/[0.06]">
                                                <td colSpan={5} className="px-4 py-2 text-xs font-bold uppercase tracking-wide text-slate-700 dark:text-slate-200">
                                                    {section.title}
                                                    <span className="ml-2 font-semibold normal-case tracking-normal text-slate-500 dark:text-slate-400">
                                                        {formatDisplayNumber(section.liters)} ลิตร · {section.count} รายการ
                                                    </span>
                                                </td>
                                            </tr>
                                            {section.items.map((item, i) => (
                                                <tr key={item.group} className={i % 2 === 0 ? 'bg-white dark:bg-transparent' : 'bg-slate-50/70 dark:bg-white/[0.02]'}>
                                                    <td className="px-4 py-2.5 pl-6 font-medium text-slate-800 dark:text-slate-100">{item.title}</td>
                                                    <td className="px-4 py-2.5 text-right tabular-nums">{formatDisplayNumber(item.liters)}</td>
                                                    <td className="px-4 py-2.5 text-right tabular-nums text-slate-500">{item.count}</td>
                                                    <td className="px-4 py-2.5 text-right">
                                                        <Button
                                                            type="button"
                                                            variant="ghost"
                                                            className="px-2 py-1.5 text-xs inline-flex"
                                                            aria-label={`พิมพ์${fuelPrintGroupTitle(item.group)}`}
                                                            onClick={() => printFuelGroupReport(item.group, 'th')}
                                                        >
                                                            <Printer className="h-3.5 w-3.5" />
                                                        </Button>
                                                    </td>
                                                    <td className="px-4 py-2.5 text-right">
                                                        <Button
                                                            type="button"
                                                            variant="ghost"
                                                            className="px-2 py-1.5 text-xs inline-flex gap-1"
                                                            aria-label={`พิมพ์${fuelPrintGroupTitle(item.group, 'zh')}`}
                                                            onClick={() => printFuelGroupReport(item.group, 'zh')}
                                                        >
                                                            <Printer className="h-3.5 w-3.5" />
                                                            <span className="text-[10px] font-bold">中文</span>
                                                        </Button>
                                                    </td>
                                                </tr>
                                            ))}
                                            <tr className="border-b border-slate-200 font-semibold text-slate-800 dark:border-white/10 dark:text-slate-100">
                                                <td className="px-4 py-2.5 pl-6">รวม{section.title}</td>
                                                <td className="px-4 py-2.5 text-right tabular-nums">{formatDisplayNumber(section.liters)}</td>
                                                <td className="px-4 py-2.5 text-right tabular-nums">{section.count}</td>
                                                <td className="px-4 py-2.5" />
                                                <td className="px-4 py-2.5" />
                                            </tr>
                                        </Fragment>
                                    ))}
                                </tbody>
                                <tfoot>
                                    <tr className="border-t border-slate-200 dark:border-white/10 font-semibold text-slate-800 dark:text-slate-100">
                                        <td className="px-4 py-2.5">พิมพ์สรุปภาพรวม</td>
                                        <td className="px-4 py-2.5" />
                                        <td className="px-4 py-2.5" />
                                        <td className="px-4 py-2.5 text-right">
                                            <Button
                                                type="button"
                                                variant="ghost"
                                                className="px-2 py-1.5 text-xs inline-flex"
                                                aria-label={fuelPrintGroupTitle('overview')}
                                                onClick={() => printFuelGroupReport('overview', 'th')}
                                            >
                                                <Printer className="h-3.5 w-3.5" />
                                            </Button>
                                        </td>
                                        <td className="px-4 py-2.5 text-right">
                                            <Button
                                                type="button"
                                                variant="ghost"
                                                className="px-2 py-1.5 text-xs inline-flex gap-1"
                                                aria-label={fuelPrintGroupTitle('overview', 'zh')}
                                                onClick={() => printFuelGroupReport('overview', 'zh')}
                                            >
                                                <Printer className="h-3.5 w-3.5" />
                                                <span className="text-[10px] font-bold">中文</span>
                                            </Button>
                                        </td>
                                    </tr>
                                </tfoot>
                            </table>
                        </div>
                    </Card>

                    <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
                        <SummaryTile label="รับเข้า (ถังหลัก)" value={liters(fuelReport.totals.stockInLiters)} />
                        <SummaryTile
                            label="เบิกไปถังสำรอง"
                            value={liters(fuelReport.totals.withdrawLiters)}
                            hint="ยังไม่นับเป็นใช้"
                        />
                        <SummaryTile
                            label="ใช้แล้ว"
                            value={liters(fuelReport.totals.usageLiters)}
                            hint={`กระทบยอด ${formatDisplayNumber(fuelReport.totals.stockInLiters - fuelReport.totals.usageLiters)} ลิตร`}
                        />
                        <SummaryTile
                            label="คงเหลือถังหลัก"
                            value={liters(remainingStock.Diesel)}
                            hint={`ถังสำรอง ${formatDisplayNumber(remainingStock.DieselReserve ?? 0)} ลิตร`}
                        />
                    </div>
                    {(remainingStock.DieselReserve ?? 0) < 0 || remainingStock.reserveShortfallLiters > 0 ? (
                        <div className="rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-900 dark:border-amber-500/40 dark:bg-amber-950/30 dark:text-amber-100">
                            ถังสำรองติดลบ {formatDisplayNumber(Math.abs(remainingStock.DieselReserve ?? 0))} ลิตร
                            — ขาดบันทึกเบิกเติมเครื่องจักร (โอนเข้าถังสำรอง) ประมาณ{' '}
                            {formatDisplayNumber(remainingStock.reserveShortfallLiters || Math.abs(remainingStock.DieselReserve ?? 0))} ลิตร
                        </div>
                    ) : null}

                    <div className="grid gap-4 lg:grid-cols-2">
                        <Card className="p-0 overflow-hidden border-slate-200/80 dark:border-white/10">
                            <div className="px-4 py-3 border-b border-slate-200 dark:border-white/10 flex items-center gap-2 bg-white dark:bg-transparent">
                                <Truck size={16} className="text-slate-500" />
                                <h4 className="text-sm font-bold tracking-wide text-slate-800 dark:text-slate-100 uppercase">สรุปตามรถ</h4>
                            </div>
                            {fuelReport.byVehicle.length === 0 ? (
                                <p className="p-6 text-sm text-slate-400 text-center">ยังไม่มีรายการใช้น้ำมันรายรถในช่วงนี้</p>
                            ) : (
                                <div className="overflow-x-auto">
                                    <table className="w-full text-sm">
                                        <thead>
                                            <tr className="text-left text-[11px] uppercase tracking-wide text-slate-500 border-b border-slate-100 dark:border-white/10">
                                                <th scope="col" className="px-4 py-2.5 font-semibold">รถ</th>
                                                <th scope="col" className="px-4 py-2.5 font-semibold text-right">ลิตร</th>
                                                <th scope="col" className="px-4 py-2.5 font-semibold text-right">รายการ</th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            {fuelReport.byVehicle.map((row, i) => (
                                                <tr key={row.vehicleId} className={i % 2 === 0 ? 'bg-white dark:bg-transparent' : 'bg-slate-50/70 dark:bg-white/[0.02]'}>
                                                    <td className="px-4 py-2.5 font-medium text-slate-800 dark:text-slate-100">{row.vehicleId}</td>
                                                    <td className="px-4 py-2.5 text-right tabular-nums text-slate-700 dark:text-slate-200">{formatDisplayNumber(row.liters)}</td>
                                                    <td className="px-4 py-2.5 text-right tabular-nums text-slate-500">{row.count}</td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                </div>
                            )}
                        </Card>

                        <Card className="p-0 overflow-hidden border-slate-200/80 dark:border-white/10">
                            <div className="px-4 py-3 border-b border-slate-200 dark:border-white/10">
                                <h4 className="text-sm font-bold tracking-wide text-slate-800 dark:text-slate-100 uppercase">สรุปรายวัน</h4>
                            </div>
                            {fuelReport.byDay.length === 0 ? (
                                <p className="p-6 text-sm text-slate-400 text-center">ไม่มีข้อมูลในช่วงวันที่ที่เลือก</p>
                            ) : (
                                <div className="overflow-x-auto max-h-80">
                                    <table className="w-full text-sm">
                                        <thead className="sticky top-0 bg-white dark:bg-slate-950 z-10">
                                            <tr className="text-left text-[11px] uppercase tracking-wide text-slate-500 border-b border-slate-100 dark:border-white/10">
                                                <th scope="col" className="px-4 py-2.5 font-semibold">วันที่</th>
                                                <th scope="col" className="px-4 py-2.5 font-semibold text-right">รับเข้า</th>
                                                <th scope="col" className="px-4 py-2.5 font-semibold text-right">ใช้ (ลิตร)</th>
                                                <th scope="col" className="px-4 py-2.5 font-semibold text-right">รายการ</th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            {fuelReport.byDay.map((row, i) => (
                                                <tr key={row.date} className={i % 2 === 0 ? 'bg-white dark:bg-transparent' : 'bg-slate-50/70 dark:bg-white/[0.02]'}>
                                                    <td className="px-4 py-2.5 text-slate-800 dark:text-slate-100 whitespace-nowrap">{formatDateBE(row.date)}</td>
                                                    <td className="px-4 py-2.5 text-right tabular-nums">{formatDisplayNumber(row.stockInLiters)}</td>
                                                    <td className="px-4 py-2.5 text-right tabular-nums">{formatDisplayNumber(row.usageLiters)}</td>
                                                    <td className="px-4 py-2.5 text-right tabular-nums text-slate-500">{row.count}</td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                </div>
                            )}
                        </Card>
                    </div>

                    <Card className="p-0 overflow-hidden border-slate-200/80 dark:border-white/10">
                        <div className="px-4 py-3 border-b border-slate-200 dark:border-white/10">
                            <h4 className="text-sm font-bold tracking-wide text-slate-800 dark:text-slate-100 uppercase">รายละเอียดรายการ</h4>
                        </div>
                        {fuelReport.rows.length === 0 ? (
                            <p className="p-6 text-sm text-slate-400 text-center">ไม่พบรายการน้ำมันในช่วงนี้</p>
                        ) : (
                            <div className="overflow-x-auto">
                                <table className="w-full text-sm">
                                    <thead>
                                        <tr className="text-left text-[11px] uppercase tracking-wide text-slate-500 border-b border-slate-100 dark:border-white/10">
                                            <th scope="col" className="px-4 py-2.5 font-semibold">วันที่</th>
                                            <th scope="col" className="px-4 py-2.5 font-semibold">รถ</th>
                                            <th scope="col" className="px-4 py-2.5 font-semibold text-right">ลิตร</th>
                                            <th scope="col" className="px-4 py-2.5 font-semibold">รายละเอียด</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {(() => {
                                            const byDate = new Map<string, typeof fuelReport.rows>();
                                            for (const row of fuelReport.rows) {
                                                const list = byDate.get(row.date) || [];
                                                list.push(row);
                                                byDate.set(row.date, list);
                                            }
                                            return [...byDate.entries()].map(([date, dayRows]) => {
                                                const dayLiters = dayRows.reduce((s, r) => s + r.liters, 0);
                                                return (
                                                    <Fragment key={date}>
                                                        <tr className="bg-slate-100/80 dark:bg-white/[0.06]">
                                                            <td colSpan={4} className="px-4 py-2 text-xs font-bold text-slate-700 dark:text-slate-200">
                                                                {formatDateBE(date)}
                                                                <span className="ml-2 font-semibold text-slate-500 dark:text-slate-400">
                                                                    {formatDisplayNumber(dayLiters)} ลิตร · {dayRows.length} รายการ
                                                                </span>
                                                            </td>
                                                        </tr>
                                                        {dayRows.map((row, i) => (
                                                            <tr key={row.id} className={i % 2 === 0 ? 'bg-white dark:bg-transparent' : 'bg-slate-50/70 dark:bg-white/[0.02]'}>
                                                                <td className="px-4 py-2.5 whitespace-nowrap text-slate-800 dark:text-slate-100">{formatDateBE(row.date)}</td>
                                                                <td className="px-4 py-2.5">{row.vehicleId || '—'}</td>
                                                                <td className="px-4 py-2.5 text-right tabular-nums font-medium">{formatDisplayNumber(row.liters)}</td>
                                                                <td className="px-4 py-2.5 text-slate-600 dark:text-slate-300 max-w-xs truncate">{row.description || '—'}</td>
                                                            </tr>
                                                        ))}
                                                    </Fragment>
                                                );
                                            });
                                        })()}
                                    </tbody>
                                </table>
                            </div>
                        )}
                    </Card>
                </>
            ) : (
                <>
                    <div className="flex flex-wrap gap-2 print:hidden" role="tablist" aria-label="ประเภทรายงานการใช้รถ">
                        {VEHICLE_REPORT_TABS.map((tab) => (
                            <button
                                key={tab.id}
                                type="button"
                                role="tab"
                                aria-selected={vehicleKind === tab.id}
                                onClick={() => switchVehicleReport(tab.id)}
                                className={`inline-flex items-center rounded-xl px-3.5 py-2 text-sm font-bold transition ${
                                    vehicleKind === tab.id
                                        ? 'bg-sky-600 text-white shadow-sm'
                                        : 'bg-white text-slate-700 ring-1 ring-slate-200 hover:bg-slate-50 dark:bg-white/5 dark:text-slate-200 dark:ring-white/15'
                                }`}
                            >
                                {tab.label}
                            </button>
                        ))}
                    </div>

                    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between print:hidden">
                        <div className="min-w-0">
                            <p className="text-xs font-semibold uppercase tracking-[0.12em] text-slate-500 dark:text-slate-400">เอกสารรายงาน</p>
                            <h3 className="mt-1 text-xl font-bold tracking-tight text-slate-900 dark:text-slate-50 flex items-center gap-2">
                                <Truck className="h-5 w-5 text-slate-700 dark:text-slate-200 shrink-0" />
                                {activeVehicleTab.label}
                            </h3>
                            <p className="mt-1 text-sm text-slate-600 dark:text-slate-400 max-w-2xl">
                                รายงานแยกตามประเภทรถ — กรองวันที่ ดูสรุปตามรถแล้วพิมพ์ได้รายคัน และดูรายละเอียดแยกเป็นรายวัน
                            </p>
                        </div>
                        <div className="flex flex-wrap gap-2 shrink-0">
                            <Button type="button" variant="outline" className="px-3" onClick={exportVehicleCsv}>
                                <FileDown className="h-4 w-4" /> Export CSV
                            </Button>
                            <Button
                                type="button"
                                variant="outline"
                                className="px-3 text-xs sm:text-sm"
                                aria-label={vehiclePrintGroupTitle(vehiclePrintGroup)}
                                onClick={() => printVehicleGroupReport(vehiclePrintGroup)}
                            >
                                <Printer className="h-4 w-4 shrink-0" />
                                พิมพ์รายงานนี้
                            </Button>
                            <Button
                                type="button"
                                variant="outline"
                                className="px-3 text-xs sm:text-sm"
                                aria-label={vehiclePrintGroupTitle(vehiclePrintGroup, 'zh')}
                                onClick={() => printVehicleGroupReport(vehiclePrintGroup, 'zh')}
                            >
                                <Printer className="h-4 w-4 shrink-0" />
                                พิมพ์+ภาษาจีน
                            </Button>
                        </div>
                    </div>

                    <Card className="p-0 overflow-hidden border-slate-200/80 dark:border-white/10 shadow-sm">
                        <div className="border-b border-slate-200 dark:border-white/10 bg-slate-50/80 dark:bg-white/[0.03] px-5 py-4">
                            <p className="text-sm font-semibold text-slate-800 dark:text-slate-100">{orgTitle}</p>
                            {orgLine ? <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">{orgLine}</p> : null}
                            <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
                                ช่วง <span className="font-medium text-slate-800 dark:text-slate-100">{rangeLabel}</span>
                                <span className="text-slate-400 mx-1.5">·</span>
                                {vehicleReport.totals.count} รายการ · {vehicleReport.totals.vehicleCount} คัน
                            </p>
                        </div>

                        <div className="p-4 sm:p-5 space-y-4 print:hidden">
                            <div className="grid gap-4 lg:grid-cols-2">
                                <ThaiDateSelect label="ตั้งแต่" value={start} onChange={setStart} />
                                <ThaiDateSelect label="ถึง" value={end} onChange={setEnd} />
                            </div>
                            <div className="grid gap-3 sm:grid-cols-2">
                                <Select label="รถ" value={vehicleId} onChange={e => setVehicleId(e.target.value)} className={selectClass}>
                                    <option value="">ทุกคัน</option>
                                    {opsVehicleOptions.map(name => (
                                        <option key={name} value={name}>{name}</option>
                                    ))}
                                </Select>
                                <div className="flex flex-wrap items-end gap-2">
                                    <Button type="button" variant="ghost" className="px-3 py-2 text-xs" onClick={() => applyBounds(monthBoundsFromYmd(today))}>เดือนนี้</Button>
                                    <Button type="button" variant="ghost" className="px-3 py-2 text-xs" onClick={() => applyBounds(shiftMonthBounds(today, -1))}>เดือนที่แล้ว</Button>
                                    <Button type="button" variant="ghost" className="px-3 py-2 text-xs" onClick={() => applyBounds(yearBoundsFromYmd(today))}>ปีนี้</Button>
                                </div>
                            </div>
                        </div>
                    </Card>

                    <div className="grid grid-cols-2 gap-3 lg:grid-cols-3">
                        <SummaryTile
                            label="รายการ"
                            value={formatDisplayNumber(vehicleReport.totals.count)}
                        />
                        <SummaryTile
                            label="จำนวนรถ"
                            value={`${formatDisplayNumber(vehicleReport.totals.vehicleCount)} คัน`}
                        />
                        <SummaryTile
                            label="ประเภท"
                            value={vehicleKindLabel(vehicleKind)}
                        />
                    </div>

                    <Card className="p-0 overflow-hidden border-slate-200/80 dark:border-white/10">
                        <div className="px-4 py-3 border-b border-slate-200 dark:border-white/10 flex items-center gap-2">
                            <Truck size={16} className="text-slate-500" />
                            <h4 className="text-sm font-bold tracking-wide text-slate-800 dark:text-slate-100 uppercase">สรุปตามรถ</h4>
                        </div>
                        {vehicleReport.byVehicle.length === 0 ? (
                            <p className="p-6 text-sm text-slate-400 text-center">ยังไม่มีรายการใช้รถในช่วงนี้</p>
                        ) : (
                            <div className="overflow-x-auto">
                                <table className="w-full text-sm">
                                    <thead>
                                        <tr className="text-left text-[11px] uppercase tracking-wide text-slate-500 border-b border-slate-100 dark:border-white/10">
                                            <th scope="col" className="px-4 py-2.5 font-semibold">รถ</th>
                                            <th scope="col" className="px-4 py-2.5 font-semibold text-right">รายการ</th>
                                            <th scope="col" className="px-4 py-2.5 font-semibold text-right w-24">พิมพ์</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {vehicleReport.byVehicle.map((row, i) => (
                                            <tr key={`${row.kind}-${row.vehicleId}`} className={i % 2 === 0 ? 'bg-white dark:bg-transparent' : 'bg-slate-50/70 dark:bg-white/[0.02]'}>
                                                <td className="px-4 py-2.5 font-medium text-slate-800 dark:text-slate-100">{row.vehicleId}</td>
                                                <td className="px-4 py-2.5 text-right tabular-nums text-slate-500">{row.count}</td>
                                                <td className="px-4 py-2.5 text-right">
                                                    <Button
                                                        type="button"
                                                        variant="ghost"
                                                        className="px-2 py-1.5 text-xs inline-flex"
                                                        aria-label={`พิมพ์${row.vehicleId}`}
                                                        onClick={() => printVehicleGroupReport(vehiclePrintGroup, 'th', { vehicleId: row.vehicleId })}
                                                    >
                                                        <Printer className="h-3.5 w-3.5" />
                                                    </Button>
                                                </td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                        )}
                    </Card>

                    <Card className="p-0 overflow-hidden border-slate-200/80 dark:border-white/10">
                        <div className="px-4 py-3 border-b border-slate-200 dark:border-white/10">
                            <h4 className="text-sm font-bold tracking-wide text-slate-800 dark:text-slate-100 uppercase">รายละเอียดรายวัน</h4>
                        </div>
                        {vehicleReport.rows.length === 0 ? (
                            <p className="p-6 text-sm text-slate-400 text-center">ไม่พบรายการใช้รถในช่วงนี้</p>
                        ) : (
                            <div className="space-y-4 p-3 sm:p-4">
                                {(() => {
                                    const byDate = new Map<string, typeof vehicleReport.rows>();
                                    for (const row of vehicleReport.rows) {
                                        const list = byDate.get(row.date) || [];
                                        list.push(row);
                                        byDate.set(row.date, list);
                                    }
                                    return [...byDate.entries()].map(([date, dayRows]) => (
                                        <section
                                            key={date}
                                            className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm dark:border-white/10 dark:bg-slate-900/40"
                                        >
                                            <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-200 bg-slate-100 px-4 py-3 dark:border-white/10 dark:bg-slate-800/80">
                                                <h5 className="text-sm font-bold text-slate-900 dark:text-slate-50">
                                                    {formatDateBE(date)}
                                                </h5>
                                                <span className="rounded-full bg-white px-2.5 py-1 text-[11px] font-bold text-slate-600 ring-1 ring-slate-200 dark:bg-slate-900 dark:text-slate-300 dark:ring-white/15">
                                                    {dayRows.length} รายการ
                                                </span>
                                            </div>
                                            <div className="overflow-x-auto">
                                                <table className="w-full text-sm">
                                                    <thead>
                                                        <tr className="text-left text-[11px] uppercase tracking-wide text-slate-500 border-b border-slate-100 dark:border-white/10">
                                                            <th scope="col" className="px-4 py-2.5 font-semibold">รถ</th>
                                                            <th scope="col" className="px-4 py-2.5 font-semibold">คนขับ</th>
                                                            <th scope="col" className="px-4 py-2.5 font-semibold">รายละเอียด</th>
                                                        </tr>
                                                    </thead>
                                                    <tbody>
                                                        {dayRows.map((row, i) => (
                                                            <tr
                                                                key={row.id}
                                                                className={i % 2 === 0 ? 'bg-white dark:bg-transparent' : 'bg-slate-50/80 dark:bg-white/[0.03]'}
                                                            >
                                                                <td className="px-4 py-3 font-medium text-slate-800 dark:text-slate-100">{row.vehicleId}</td>
                                                                <td className="px-4 py-3 text-slate-700 dark:text-slate-200">{row.driverLabel}</td>
                                                                <td className="px-4 py-3 text-slate-600 dark:text-slate-300">{row.description || '—'}</td>
                                                            </tr>
                                                        ))}
                                                    </tbody>
                                                </table>
                                            </div>
                                        </section>
                                    ));
                                })()}
                            </div>
                        )}
                    </Card>
                </>
            )}
        </div>
    );
};

export default ReportsModule;
