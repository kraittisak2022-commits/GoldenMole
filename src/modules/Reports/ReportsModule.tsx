import { useMemo, useState } from 'react';
import { FileDown, Fuel, Printer, Truck } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Select from '../../components/ui/Select';
import type { AppSettings, Transaction } from '../../types';
import {
    THAI_MONTHS,
    computeFuelStockBalances,
    daysInMonth,
    formatDateBELong,
    formatDisplayNumber,
    getToday,
    normalizeDate,
    ymdFromParts,
} from '../../utils';
import {
    buildFuelUsageReport,
    fuelKindLabel,
    fuelTypeLabel,
    fuelUsageToCsv,
    fuelUsageToPrintHtml,
    monthBoundsFromYmd,
    shiftMonthBounds,
    yearBoundsFromYmd,
    type FuelTypeFilter,
    type FuelUsageKind,
} from '../../utils/fuelUsageReport';

interface ReportsModuleProps {
    transactions: Transaction[];
    settings: AppSettings;
    /** คงไว้เพื่อความเข้ากันได้กับ App — รายงานนี้ไม่แสดงยอดเงิน */
    maskAmounts?: boolean;
}

const KIND_OPTIONS: Array<{ id: '' | FuelUsageKind; label: string }> = [
    { id: '', label: 'ทุกรายการ' },
    { id: 'stock_in', label: 'รับเข้า' },
    { id: 'vehicle', label: 'เติมรถ' },
    { id: 'withdraw', label: 'เบิกจากถัง' },
    { id: 'transfer', label: 'โอนถัง' },
    { id: 'sand_sieve', label: 'ร่อนทราย' },
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

const ReportsModule = ({ transactions, settings }: ReportsModuleProps) => {
    const today = getToday();
    const initial = monthBoundsFromYmd(today);
    const [start, setStart] = useState(initial.start);
    const [end, setEnd] = useState(initial.end);
    const [vehicleId, setVehicleId] = useState('');
    const [fuelType, setFuelType] = useState<'' | FuelTypeFilter>('');
    const [kind, setKind] = useState<'' | FuelUsageKind>('');

    const orgTitle = (settings.orgProfile?.name || settings.appName || 'Goldenmole').trim();
    const orgLine = [settings.orgProfile?.address, settings.orgProfile?.phone].filter(Boolean).join(' · ');

    const vehicleOptions = useMemo(() => {
        const names = new Set<string>(settings.cars || []);
        transactions.forEach(t => {
            if (t.category === 'Fuel' && t.vehicleId) names.add(t.vehicleId);
        });
        return Array.from(names).sort((a, b) => a.localeCompare(b, 'th'));
    }, [settings.cars, transactions]);

    const report = useMemo(
        () => buildFuelUsageReport(transactions, { start, end, vehicleId, fuelType, kind }),
        [transactions, start, end, vehicleId, fuelType, kind]
    );

    const remainingStock = useMemo(() => {
        const throughEnd = transactions.filter(t => normalizeDate(t.date) <= normalizeDate(end));
        return computeFuelStockBalances(throughEnd, settings.fuelOpeningStockLiters);
    }, [transactions, end, settings.fuelOpeningStockLiters]);

    const liters = (n: number) => `${formatDisplayNumber(n)} ล.`;
    const rangeLabel = `${formatDateBELong(start)} – ${formatDateBELong(end)}`;

    const applyBounds = (bounds: { start: string; end: string }) => {
        setStart(bounds.start);
        setEnd(bounds.end);
    };

    const exportCsv = () => {
        const csv = fuelUsageToCsv(report, { start, end, vehicleId, fuelType, kind });
        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `fuel-usage-${normalizeDate(start)}-to-${normalizeDate(end)}.csv`;
        a.click();
        URL.revokeObjectURL(url);
    };

    const printReport = () => {
        const html = fuelUsageToPrintHtml({
            appName: orgTitle,
            orgSubtitle: orgLine || undefined,
            rangeLabel,
            report,
            formatDate: formatDateBELong,
        });
        const w = window.open('', '_blank');
        if (!w) return;
        w.document.open();
        w.document.write(html);
        w.document.close();
        w.focus();
        w.print();
    };

    return (
        <div className="space-y-5 print:space-y-4">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between print:hidden">
                <div className="min-w-0">
                    <p className="text-xs font-semibold uppercase tracking-[0.12em] text-slate-500 dark:text-slate-400">เอกสารรายงาน</p>
                    <h3 className="mt-1 text-xl font-bold tracking-tight text-slate-900 dark:text-slate-50 flex items-center gap-2">
                        <Fuel className="h-5 w-5 text-slate-700 dark:text-slate-200 shrink-0" />
                        รายงานการใช้น้ำมัน
                    </h3>
                    <p className="mt-1 text-sm text-slate-600 dark:text-slate-400 max-w-2xl">
                        สรุปปริมาณรับเข้า เติมรถ และเบิกน้ำมันเป็นลิตรเท่านั้น · การโอนระหว่างถังไม่นับเป็นการใช้
                    </p>
                </div>
                <div className="flex flex-wrap gap-2 shrink-0">
                    <Button type="button" variant="outline" className="px-3" onClick={exportCsv}>
                        <FileDown className="h-4 w-4" /> Export CSV
                    </Button>
                    <Button type="button" variant="outline" className="px-3" onClick={printReport}>
                        <Printer className="h-4 w-4" /> พิมพ์/PDF
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
                        {report.totals.count} รายการ
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
                            {vehicleOptions.map(name => (
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

            <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
                <SummaryTile label="รับเข้า" value={liters(report.totals.stockInLiters)} />
                <SummaryTile label="เติมรถ" value={liters(report.totals.vehicleLiters)} />
                <SummaryTile label="เบิกจากถัง" value={liters(report.totals.withdrawLiters)} hint={report.totals.transferLiters > 0 ? `โอนถัง ${formatDisplayNumber(report.totals.transferLiters)} ล.` : undefined} />
                <SummaryTile label="รวมใช้" value={liters(report.totals.usageLiters)} />
                <SummaryTile
                    label="คงเหลือ ณ วันสิ้นช่วง"
                    value={liters(remainingStock.Diesel)}
                    hint={`ถังสำรอง ${formatDisplayNumber(remainingStock.DieselReserve ?? 0)} ล.`}
                />
            </div>

            <div className="grid gap-4 lg:grid-cols-2">
                <Card className="p-0 overflow-hidden border-slate-200/80 dark:border-white/10">
                    <div className="px-4 py-3 border-b border-slate-200 dark:border-white/10 flex items-center gap-2 bg-white dark:bg-transparent">
                        <Truck size={16} className="text-slate-500" />
                        <h4 className="text-sm font-bold tracking-wide text-slate-800 dark:text-slate-100 uppercase">สรุปตามรถ</h4>
                    </div>
                    {report.byVehicle.length === 0 ? (
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
                                    {report.byVehicle.map((row, i) => (
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
                    {report.byDay.length === 0 ? (
                        <p className="p-6 text-sm text-slate-400 text-center">ไม่มีข้อมูลในช่วงวันที่ที่เลือก</p>
                    ) : (
                        <div className="overflow-x-auto max-h-80">
                            <table className="w-full text-sm">
                                <thead className="sticky top-0 bg-white dark:bg-slate-950 z-10">
                                    <tr className="text-left text-[11px] uppercase tracking-wide text-slate-500 border-b border-slate-100 dark:border-white/10">
                                        <th scope="col" className="px-4 py-2.5 font-semibold">วันที่</th>
                                        <th scope="col" className="px-4 py-2.5 font-semibold text-right">รับเข้า</th>
                                        <th scope="col" className="px-4 py-2.5 font-semibold text-right">ใช้ (ล.)</th>
                                        <th scope="col" className="px-4 py-2.5 font-semibold text-right">รายการ</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {report.byDay.map((row, i) => (
                                        <tr key={row.date} className={i % 2 === 0 ? 'bg-white dark:bg-transparent' : 'bg-slate-50/70 dark:bg-white/[0.02]'}>
                                            <td className="px-4 py-2.5 text-slate-800 dark:text-slate-100 whitespace-nowrap">{formatDateBELong(row.date)}</td>
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
                {report.rows.length === 0 ? (
                    <p className="p-6 text-sm text-slate-400 text-center">ไม่พบรายการน้ำมันในช่วงนี้</p>
                ) : (
                    <div className="overflow-x-auto">
                        <table className="w-full text-sm">
                            <thead>
                                <tr className="text-left text-[11px] uppercase tracking-wide text-slate-500 border-b border-slate-100 dark:border-white/10">
                                    <th scope="col" className="px-4 py-2.5 font-semibold">วันที่</th>
                                    <th scope="col" className="px-4 py-2.5 font-semibold">ประเภท</th>
                                    <th scope="col" className="px-4 py-2.5 font-semibold">น้ำมัน</th>
                                    <th scope="col" className="px-4 py-2.5 font-semibold">รถ</th>
                                    <th scope="col" className="px-4 py-2.5 font-semibold text-right">ลิตร</th>
                                    <th scope="col" className="px-4 py-2.5 font-semibold">รายละเอียด</th>
                                </tr>
                            </thead>
                            <tbody>
                                {report.rows.map((row, i) => (
                                    <tr key={row.id} className={i % 2 === 0 ? 'bg-white dark:bg-transparent' : 'bg-slate-50/70 dark:bg-white/[0.02]'}>
                                        <td className="px-4 py-2.5 whitespace-nowrap text-slate-800 dark:text-slate-100">{formatDateBELong(row.date)}</td>
                                        <td className="px-4 py-2.5">{fuelKindLabel(row.kind)}</td>
                                        <td className="px-4 py-2.5">{fuelTypeLabel(row.fuelType)}</td>
                                        <td className="px-4 py-2.5">{row.vehicleId || '—'}</td>
                                        <td className="px-4 py-2.5 text-right tabular-nums font-medium">{formatDisplayNumber(row.liters)}</td>
                                        <td className="px-4 py-2.5 text-slate-600 dark:text-slate-300 max-w-xs truncate">{row.description || '—'}</td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </Card>
        </div>
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

export default ReportsModule;
