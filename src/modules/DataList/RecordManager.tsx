import { useState, useMemo } from 'react';
import { Trash2 } from 'lucide-react';
import Card from '../../components/ui/Card';
import FormatNumber from '../../components/ui/FormatNumber';
import { normalizeDate } from '../../utils';
import { Transaction } from '../../types';

const CATEGORY_LABELS: Record<string, string> = {
    Labor: 'ค่าแรง/ลา',
    Vehicle: 'รถ',
    Fuel: 'น้ำมัน',
    Maintenance: 'ซ่อมบำรุง',
    Income: 'รายรับ',
    Leave: 'ลา',
    DailyLog: 'บันทึกงาน',
    Land: 'ที่ดิน',
    Utilities: 'สาธารณูปโภค',
};

export interface RecordManagerProps {
    transactions: Transaction[];
    onDeleteTransaction?: (id: string) => void;
    /** โหมดมือถือ: ตัวกรองสั้น + การ์ดแทนตาราง */
    compact?: boolean;
    /** ธีมมืด (ส่งจาก MobileFieldApp) */
    darkMode?: boolean;
}

const RecordManager = ({ transactions, onDeleteTransaction, compact = false, darkMode = false }: RecordManagerProps) => {
    const [filterMode, setFilterMode] = useState<'all' | 'month' | 'date'>('all');
    const [filterMonth, setFilterMonth] = useState(() => {
        const d = new Date();
        return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    });
    const [filterDate, setFilterDate] = useState('');
    const [searchQuery, setSearchQuery] = useState('');

    const filtered = useMemo(() => {
        let list = [...transactions];
        if (filterMode === 'month' && filterMonth) {
            const [y, m] = filterMonth.split('-').map(Number);
            const first = `${y}-${String(m).padStart(2, '0')}-01`;
            const lastDay = new Date(y, m, 0).getDate();
            const last = `${y}-${String(m).padStart(2, '0')}-${String(lastDay).padStart(2, '0')}`;
            list = list.filter(t => {
                const d = normalizeDate(t.date);
                return d >= first && d <= last;
            });
        } else if (filterMode === 'date' && filterDate) {
            const d = normalizeDate(filterDate);
            list = list.filter(t => normalizeDate(t.date) === d);
        }
        const q = searchQuery.trim().toLowerCase();
        if (q) {
            list = list.filter(t =>
                (t.description || '').toLowerCase().includes(q) ||
                (t.category || '').toLowerCase().includes(q) ||
                (CATEGORY_LABELS[t.category || ''] || '').toLowerCase().includes(q)
            );
        }
        return list;
    }, [transactions, filterMode, filterMonth, filterDate, searchQuery]);

    const byDay = useMemo(() => {
        const map = new Map<string, Transaction[]>();
        filtered.forEach(t => {
            const d = normalizeDate(t.date);
            if (!map.has(d)) map.set(d, []);
            map.get(d)!.push(t);
        });
        const entries = Array.from(map.entries()).sort((a, b) => b[0].localeCompare(a[0]));
        return entries;
    }, [filtered]);

    const formatDayHeader = (dateStr: string) => {
        const [y, m, d] = dateStr.split('-').map(Number);
        const date = new Date(y, (m || 1) - 1, d || 1);
        return date.toLocaleDateString('th-TH', { timeZone: 'Asia/Bangkok', weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
    };

    const formatDayShort = (dateStr: string) => {
        const [y, m, d] = dateStr.split('-').map(Number);
        const date = new Date(y, (m || 1) - 1, d || 1);
        return date.toLocaleDateString('th-TH', { timeZone: 'Asia/Bangkok', weekday: 'short', day: 'numeric', month: 'short' });
    };

    const chip = (active: boolean) =>
        `min-h-[44px] shrink-0 rounded-full px-4 text-sm font-bold touch-manipulation ${
            active
                ? 'bg-blue-600 text-white shadow-md dark:bg-blue-500'
                : darkMode
                  ? 'border border-slate-600 bg-slate-800 text-slate-200'
                  : 'border border-slate-200 bg-white text-slate-700'
        }`;

    if (compact) {
        return (
            <div className="animate-fade-in space-y-3">
                <div className="flex flex-col gap-2">
                    <div className="flex gap-2 overflow-x-auto pb-1 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
                        {[
                            { id: 'all' as const, label: 'ทั้งหมด' },
                            { id: 'month' as const, label: 'เดือน' },
                            { id: 'date' as const, label: 'วันที่' },
                        ].map(opt => {
                            const active =
                                (opt.id === 'all' && filterMode === 'all') ||
                                (opt.id === 'month' && filterMode === 'month') ||
                                (opt.id === 'date' && filterMode === 'date');
                            return (
                                <button
                                    key={opt.id}
                                    type="button"
                                    onClick={() => {
                                        if (opt.id === 'all') setFilterMode('all');
                                        if (opt.id === 'month') setFilterMode('month');
                                        if (opt.id === 'date') setFilterMode('date');
                                    }}
                                    className={chip(active)}
                                >
                                    {opt.label}
                                </button>
                            );
                        })}
                    </div>
                    {filterMode === 'month' && (
                        <input
                            type="month"
                            value={filterMonth}
                            onChange={e => setFilterMonth(e.target.value)}
                            className={`min-h-[48px] w-full rounded-2xl border px-4 text-base font-semibold ${
                                darkMode ? 'border-slate-600 bg-slate-800 text-white' : 'border-slate-200 bg-white text-slate-900'
                            }`}
                        />
                    )}
                    {filterMode === 'date' && (
                        <input
                            type="date"
                            value={filterDate}
                            onChange={e => setFilterDate(e.target.value)}
                            className={`min-h-[48px] w-full rounded-2xl border px-4 text-base font-semibold ${
                                darkMode ? 'border-slate-600 bg-slate-800 text-white' : 'border-slate-200 bg-white text-slate-900'
                            }`}
                        />
                    )}
                    <input
                        type="search"
                        enterKeyHint="search"
                        placeholder="ค้นหา..."
                        value={searchQuery}
                        onChange={e => setSearchQuery(e.target.value)}
                        className={`min-h-[48px] w-full rounded-2xl border px-4 text-base ${
                            darkMode ? 'border-slate-600 bg-slate-800 text-white placeholder:text-slate-500' : 'border-slate-200 bg-white placeholder:text-slate-400'
                        }`}
                    />
                </div>

                <div className="max-h-[min(70dvh,560px)] min-h-[120px] space-y-4 overflow-y-auto overscroll-contain pb-2">
                    {byDay.length === 0 ? (
                        <p className={`py-10 text-center text-sm ${darkMode ? 'text-slate-500' : 'text-slate-500'}`}>ไม่มีรายการ</p>
                    ) : (
                        byDay.map(([day, list]) => (
                            <div key={day}>
                                <p
                                    className={`sticky top-0 z-[1] mb-2 px-1 py-1 text-xs font-black ${
                                        darkMode ? 'bg-slate-950/90 text-slate-400' : 'bg-[#e8edf5]/95 text-slate-500'
                                    }`}
                                >
                                    {formatDayShort(day)} · {list.length} รายการ
                                </p>
                                <div className="space-y-2">
                                    {list.map(t => (
                                        <div
                                            key={t.id}
                                            className={`flex items-stretch gap-3 rounded-2xl border p-3 shadow-sm ${
                                                darkMode ? 'border-slate-700 bg-slate-800/80' : 'border-slate-100 bg-white'
                                            }`}
                                        >
                                            <div className="min-w-0 flex-1">
                                                <span
                                                    className={`inline-block rounded-lg px-2 py-0.5 text-[11px] font-bold ${
                                                        darkMode ? 'bg-slate-700 text-slate-200' : 'bg-slate-100 text-slate-700'
                                                    }`}
                                                >
                                                    {CATEGORY_LABELS[t.category || ''] || t.category}
                                                </span>
                                                <p className={`mt-1 line-clamp-2 text-sm font-semibold leading-snug ${darkMode ? 'text-white' : 'text-slate-800'}`}>
                                                    {t.description || '—'}
                                                </p>
                                            </div>
                                            <div className="flex shrink-0 flex-col items-end justify-between">
                                                <span
                                                    className={`font-mono text-lg font-black tabular-nums ${
                                                        t.type === 'Income' ? 'text-emerald-500' : 'text-rose-500 dark:text-rose-400'
                                                    }`}
                                                >
                                                    {t.type === 'Income' ? '+' : ''}
                                                    <FormatNumber value={t.amount} />
                                                </span>
                                                {onDeleteTransaction && (
                                                    <button
                                                        type="button"
                                                        onClick={() => {
                                                            if (confirm('ลบรายการนี้?')) onDeleteTransaction(t.id);
                                                        }}
                                                        className="mt-1 rounded-xl p-2 text-slate-400 hover:bg-red-500/15 hover:text-red-500 touch-manipulation"
                                                        aria-label="ลบ"
                                                    >
                                                        <Trash2 size={18} />
                                                    </button>
                                                )}
                                            </div>
                                        </div>
                                    ))}
                                </div>
                            </div>
                        ))
                    )}
                </div>
            </div>
        );
    }

    return (
        <div className="space-y-4 animate-fade-in">
            <Card className="p-0 overflow-hidden">
                <div className="p-3 sm:p-4 bg-slate-50 dark:bg-white/[0.04] border-b border-slate-200 dark:border-white/10 sticky top-0 z-10">
                    <h3 className="font-bold text-slate-800 dark:text-slate-100 mb-4">รายการบันทึก</h3>
                    <div className="flex flex-col sm:flex-row gap-3 sm:gap-4 flex-wrap">
                        <div className="flex flex-wrap items-center gap-2">
                            <span className="text-sm font-medium text-slate-600 dark:text-slate-400">ช่วงเวลา:</span>
                            <label className="flex items-center gap-1.5 cursor-pointer touch-manipulation">
                                <input type="radio" name="period" checked={filterMode === 'all'} onChange={() => setFilterMode('all')} className="accent-slate-700 min-h-[1.25rem] min-w-[1.25rem]" />
                                <span className="text-sm text-slate-700 dark:text-slate-300">ทั้งหมด</span>
                            </label>
                            <label className="flex items-center gap-1.5 cursor-pointer touch-manipulation">
                                <input type="radio" name="period" checked={filterMode === 'month'} onChange={() => setFilterMode('month')} className="accent-slate-700 min-h-[1.25rem] min-w-[1.25rem]" />
                                <span className="text-sm text-slate-700 dark:text-slate-300">เดือน</span>
                            </label>
                            {filterMode === 'month' && (
                                <input
                                    type="month"
                                    value={filterMonth}
                                    onChange={(e) => setFilterMonth(e.target.value)}
                                    className="border border-slate-300 dark:border-white/20 rounded-xl px-3 py-2.5 text-base bg-white dark:bg-white/5 text-slate-800 dark:text-slate-200 min-h-[44px]"
                                />
                            )}
                            <label className="flex items-center gap-1.5 cursor-pointer touch-manipulation">
                                <input type="radio" name="period" checked={filterMode === 'date'} onChange={() => setFilterMode('date')} className="accent-slate-700 min-h-[1.25rem] min-w-[1.25rem]" />
                                <span className="text-sm text-slate-700 dark:text-slate-300">วันที่</span>
                            </label>
                            {filterMode === 'date' && (
                                <input
                                    type="date"
                                    value={filterDate}
                                    onChange={(e) => setFilterDate(e.target.value)}
                                    className="border border-slate-300 dark:border-white/20 rounded-xl px-3 py-2.5 text-base bg-white dark:bg-white/5 text-slate-800 dark:text-slate-200 min-h-[44px]"
                                />
                            )}
                        </div>
                        <div className="flex-1 min-w-[180px]">
                            <input
                                type="search"
                                enterKeyHint="search"
                                placeholder="ค้นหา (รายละเอียด, ประเภท)..."
                                value={searchQuery}
                                onChange={(e) => setSearchQuery(e.target.value)}
                                className="w-full border border-slate-300 dark:border-white/20 rounded-xl px-3 py-3 text-base bg-white dark:bg-white/5 text-slate-800 dark:text-slate-200 placeholder-slate-400 min-h-[44px]"
                            />
                        </div>
                    </div>
                    {filtered.length > 0 && (
                        <p className="text-xs text-slate-500 dark:text-slate-400 mt-2">
                            แสดง {filtered.length} รายการ {byDay.length > 0 && `ใน ${byDay.length} วัน`}
                        </p>
                    )}
                </div>
                <div className="max-h-[calc(100dvh-280px)] min-h-[200px] overflow-y-auto overscroll-contain">
                    {byDay.length === 0 ? (
                        <div className="p-8 text-center text-slate-500 dark:text-slate-400 text-sm">ไม่มีรายการที่ตรงกับเงื่อนไข</div>
                    ) : (
                        <div className="divide-y divide-slate-200 dark:divide-white/10">
                            {byDay.map(([day, list]) => (
                                <div key={day} className="bg-white dark:bg-white/[0.02]">
                                    <div className="sticky top-0 z-10 px-3 sm:px-4 py-2.5 bg-slate-100 dark:bg-slate-800/80 border-b border-slate-200 dark:border-white/10 flex items-center justify-between">
                                        <span className="font-bold text-slate-800 dark:text-slate-100 text-sm">{formatDayHeader(day)}</span>
                                        <span className="text-xs text-slate-500 dark:text-slate-400">{list.length} รายการ</span>
                                    </div>
                                    <div className="overflow-x-auto">
                                        <div className="sm:hidden text-[11px] text-slate-400 dark:text-slate-500 px-3 pt-2 pb-1">
                                            เลื่อนในแนวนอนเพื่อดูข้อมูลครบถ้วน
                                        </div>
                                        <table className="w-full text-sm text-left min-w-[480px]">
                                            <thead>
                                                <tr className="border-b border-slate-100 dark:border-white/5">
                                                    <th className="p-2 sm:p-3 text-slate-500 dark:text-slate-400 font-medium whitespace-nowrap">ประเภท</th>
                                                    <th className="p-2 sm:p-3 text-slate-500 dark:text-slate-400 font-medium max-sm:w-1/2">รายละเอียด</th>
                                                    <th className="p-2 sm:p-3 text-right text-slate-500 dark:text-slate-400 font-medium">จำนวนเงิน</th>
                                                    {onDeleteTransaction && <th className="p-2 sm:p-3 w-10"></th>}
                                                </tr>
                                            </thead>
                                            <tbody>
                                                {list.map(t => (
                                                    <tr key={t.id} className="border-b border-slate-50 dark:border-white/5 hover:bg-slate-50 dark:hover:bg-white/[0.04]">
                                                        <td className="p-2 sm:p-3 whitespace-nowrap">
                                                            <span className="text-xs px-2 py-0.5 rounded bg-slate-200 dark:bg-slate-600 text-slate-700 dark:text-slate-200">
                                                                {CATEGORY_LABELS[t.category || ''] || t.category}
                                                            </span>
                                                        </td>
                                                        <td className="p-2 sm:p-3 text-slate-700 dark:text-slate-300 max-w-[160px] sm:max-w-none truncate sm:whitespace-normal" title={t.description}>{t.description}</td>
                                                        <td className={`p-2 sm:p-3 text-right font-bold whitespace-nowrap ${t.type === 'Income' ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-500 dark:text-red-400'}`}>
                                                            {t.type === 'Income' ? '+' : ''}<FormatNumber value={t.amount} />
                                                        </td>
                                                        {onDeleteTransaction && (
                                                            <td className="p-2 sm:p-3 text-center">
                                                                <button type="button" onClick={() => { if (confirm('ลบรายการนี้?')) onDeleteTransaction(t.id); }} className="p-2 min-w-[44px] min-h-[44px] inline-flex items-center justify-center rounded-lg text-slate-400 hover:text-red-500 dark:hover:text-red-400 touch-manipulation" title="ลบ"><Trash2 size={16} /></button>
                                                            </td>
                                                        )}
                                                    </tr>
                                                ))}
                                            </tbody>
                                        </table>
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}
                </div>
            </Card>
        </div>
    );
};

export default RecordManager;
