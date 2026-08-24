import { useMemo, useState } from 'react';
import { FileDown, Fuel, Printer, Truck } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import Select from '../../components/ui/Select';
import type { AppSettings, Transaction } from '../../types';
import {
    computeFuelStockBalances,
    formatDateBE,
    formatDisplayCurrency,
    formatDisplayNumber,
    getToday,
    normalizeDate,
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

const ReportsModule = ({ transactions, settings, maskAmounts = false }: ReportsModuleProps) => {
    const today = getToday();
    const initial = monthBoundsFromYmd(today);
    const [start, setStart] = useState(initial.start);
    const [end, setEnd] = useState(initial.end);
    const [vehicleId, setVehicleId] = useState('');
    const [fuelType, setFuelType] = useState<'' | FuelTypeFilter>('');
    const [kind, setKind] = useState<'' | FuelUsageKind>('');

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

    const money = (n: number) => (maskAmounts ? '•••' : formatDisplayCurrency(n));
    const liters = (n: number) => `${formatDisplayNumber(n)} ลิตร`;
    const rangeLabel = `${formatDateBE(start)} – ${formatDateBE(end)}`;

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
            appName: settings.appName || 'Goldenmole',
            rangeLabel,
            report,
            maskAmounts,
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
        <div className="space-y-6">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
                <div>
                    <h3 className="text-base font-bold text-slate-800 dark:text-slate-100 flex items-center gap-2">
                        <Fuel className="h-5 w-5 text-orange-600 dark:text-orange-400 shrink-0" />
                        รายงานการใช้น้ำมัน
                    </h3>
                    <p className="mt-1 text-sm text-slate-600 dark:text-slate-400 max-w-2xl">
                        สรุปปริมาณรับเข้า เติมรถ และเบิกน้ำมันตามช่วงวันที่ พร้อมพิมพ์หรือส่งออก CSV — การโอนระหว่างถังไม่นับเป็นการใช้
                    </p>
                </div>
                <div className="flex flex-wrap gap-2">
                    <Button type="button" variant="outline" className="px-3" onClick={exportCsv}>
                        <FileDown className="h-4 w-4" /> Export CSV
                    </Button>
                    <Button type="button" variant="outline" className="px-3" onClick={printReport}>
                        <Printer className="h-4 w-4" /> พิมพ์/PDF
                    </Button>
                </div>
            </div>

            <Card className="p-4 sm:p-5">
                <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                    <Input label="ตั้งแต่" type="date" value={start} onChange={e => setStart(e.target.value)} />
                    <Input label="ถึง" type="date" value={end} onChange={e => setEnd(e.target.value)} />
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
                <div className="mt-3 flex flex-wrap gap-2">
                    <Button type="button" variant="ghost" className="px-3 py-2 text-xs" onClick={() => applyBounds(monthBoundsFromYmd(today))}>เดือนนี้</Button>
                    <Button type="button" variant="ghost" className="px-3 py-2 text-xs" onClick={() => applyBounds(shiftMonthBounds(today, -1))}>เดือนที่แล้ว</Button>
                    <Button type="button" variant="ghost" className="px-3 py-2 text-xs" onClick={() => applyBounds(yearBoundsFromYmd(today))}>ปีนี้</Button>
                </div>
                <p className="mt-2 text-xs text-slate-500 dark:text-slate-400">ช่วงที่เลือก: {rangeLabel} · {report.totals.count} รายการ</p>
            </Card>

            <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
                <SummaryTile label="รับเข้า" value={liters(report.totals.stockInLiters)} hint={money(report.totals.stockInAmount)} tone="slate" />
                <SummaryTile label="เติมรถ" value={liters(report.totals.vehicleLiters)} hint={money(report.totals.vehicleAmount)} tone="orange" />
                <SummaryTile label="เบิกจากถัง" value={liters(report.totals.withdrawLiters)} hint={`${formatDisplayNumber(report.totals.transferLiters)} ลิตร โอนถัง`} tone="amber" />
                <SummaryTile label="รวมใช้" value={liters(report.totals.usageLiters)} hint={money(report.totals.usageAmount)} tone="rose" />
                <SummaryTile
                    label="คงเหลือ ณ วันสิ้นช่วง"
                    value={`${formatDisplayNumber(remainingStock.Diesel)} ล.`}
                    hint={`ถังสำรอง ${formatDisplayNumber(remainingStock.DieselReserve ?? 0)} ล.`}
                    tone="emerald"
                />
            </div>

            <div className="grid gap-4 lg:grid-cols-2">
                <Card className="p-0 overflow-hidden">
                    <div className="p-4 bg-slate-50 dark:bg-white/[0.04] border-b border-slate-200 dark:border-white/10 flex items-center gap-2">
                        <Truck size={18} className="text-orange-600" />
                        <h4 className="font-bold text-slate-800 dark:text-slate-100">สรุปตามรถ</h4>
                    </div>
                    {report.byVehicle.length === 0 ? (
                        <p className="p-6 text-sm text-slate-400 text-center">ยังไม่มีรายการใช้น้ำมันรายรถในช่วงนี้</p>
                    ) : (
                        <div className="overflow-x-auto">
                            <table className="w-full text-sm">
                                <thead>
                                    <tr className="text-left text-xs uppercase tracking-wide text-slate-500">
                                        <th scope="col" className="px-4 py-2">รถ</th>
                                        <th scope="col" className="px-4 py-2 text-right">ลิตร</th>
                                        <th scope="col" className="px-4 py-2 text-right">ค่าใช้จ่าย</th>
                                        <th scope="col" className="px-4 py-2 text-right">รายการ</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-slate-100 dark:divide-white/10">
                                    {report.byVehicle.map(row => (
                                        <tr key={row.vehicleId}>
                                            <td className="px-4 py-2.5 font-medium text-slate-800 dark:text-slate-100">{row.vehicleId}</td>
                                            <td className="px-4 py-2.5 text-right tabular-nums">{formatDisplayNumber(row.liters)}</td>
                                            <td className="px-4 py-2.5 text-right tabular-nums">{money(row.amount)}</td>
                                            <td className="px-4 py-2.5 text-right tabular-nums">{row.count}</td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                </Card>

                <Card className="p-0 overflow-hidden">
                    <div className="p-4 bg-slate-50 dark:bg-white/[0.04] border-b border-slate-200 dark:border-white/10">
                        <h4 className="font-bold text-slate-800 dark:text-slate-100">สรุปรายวัน</h4>
                    </div>
                    {report.byDay.length === 0 ? (
                        <p className="p-6 text-sm text-slate-400 text-center">ไม่มีข้อมูลในช่วงวันที่ที่เลือก</p>
                    ) : (
                        <div className="overflow-x-auto max-h-80">
                            <table className="w-full text-sm">
                                <thead className="sticky top-0 bg-white dark:bg-slate-950">
                                    <tr className="text-left text-xs uppercase tracking-wide text-slate-500">
                                        <th scope="col" className="px-4 py-2">วันที่</th>
                                        <th scope="col" className="px-4 py-2 text-right">รับเข้า</th>
                                        <th scope="col" className="px-4 py-2 text-right">ใช้ (ล.)</th>
                                        <th scope="col" className="px-4 py-2 text-right">ค่าใช้จ่าย</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-slate-100 dark:divide-white/10">
                                    {report.byDay.map(row => (
                                        <tr key={row.date}>
                                            <td className="px-4 py-2.5 text-slate-800 dark:text-slate-100">{formatDateBE(row.date)}</td>
                                            <td className="px-4 py-2.5 text-right tabular-nums">{formatDisplayNumber(row.stockInLiters)}</td>
                                            <td className="px-4 py-2.5 text-right tabular-nums">{formatDisplayNumber(row.usageLiters)}</td>
                                            <td className="px-4 py-2.5 text-right tabular-nums">{money(row.usageAmount)}</td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                </Card>
            </div>

            <Card className="p-0 overflow-hidden">
                <div className="p-4 bg-slate-50 dark:bg-white/[0.04] border-b border-slate-200 dark:border-white/10">
                    <h4 className="font-bold text-slate-800 dark:text-slate-100">รายละเอียดรายการ</h4>
                </div>
                {report.rows.length === 0 ? (
                    <p className="p-6 text-sm text-slate-400 text-center">ไม่พบรายการน้ำมันในช่วงนี้</p>
                ) : (
                    <div className="overflow-x-auto">
                        <table className="w-full text-sm">
                            <thead>
                                <tr className="text-left text-xs uppercase tracking-wide text-slate-500">
                                    <th scope="col" className="px-4 py-2">วันที่</th>
                                    <th scope="col" className="px-4 py-2">ประเภท</th>
                                    <th scope="col" className="px-4 py-2">น้ำมัน</th>
                                    <th scope="col" className="px-4 py-2">รถ</th>
                                    <th scope="col" className="px-4 py-2 text-right">ลิตร</th>
                                    <th scope="col" className="px-4 py-2 text-right">บาท</th>
                                    <th scope="col" className="px-4 py-2">รายละเอียด</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-100 dark:divide-white/10">
                                {report.rows.map(row => (
                                    <tr key={row.id}>
                                        <td className="px-4 py-2.5 whitespace-nowrap">{formatDateBE(row.date)}</td>
                                        <td className="px-4 py-2.5">{fuelKindLabel(row.kind)}</td>
                                        <td className="px-4 py-2.5">{fuelTypeLabel(row.fuelType)}</td>
                                        <td className="px-4 py-2.5">{row.vehicleId || '—'}</td>
                                        <td className="px-4 py-2.5 text-right tabular-nums">{formatDisplayNumber(row.liters)}</td>
                                        <td className="px-4 py-2.5 text-right tabular-nums">{money(row.amount)}</td>
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
    tone,
}: {
    label: string;
    value: string;
    hint: string;
    tone: 'slate' | 'orange' | 'amber' | 'rose' | 'emerald';
}) => {
    const tones: Record<typeof tone, string> = {
        slate: 'bg-slate-50 dark:bg-white/[0.04]',
        orange: 'bg-orange-50/90 dark:bg-orange-500/10',
        amber: 'bg-amber-50/90 dark:bg-amber-500/10',
        rose: 'bg-rose-50/90 dark:bg-rose-500/10',
        emerald: 'bg-emerald-50/90 dark:bg-emerald-500/10',
    };
    return (
        <div className={`rounded-xl px-3 py-2.5 ${tones[tone]}`}>
            <p className="text-[11px] font-medium text-slate-500 dark:text-slate-400">{label}</p>
            <p className="text-lg font-bold tabular-nums text-slate-800 dark:text-slate-100">{value}</p>
            <p className="text-[11px] text-slate-500 dark:text-slate-400 mt-0.5">{hint}</p>
        </div>
    );
};

export default ReportsModule;
