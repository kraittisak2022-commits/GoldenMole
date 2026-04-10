import { useState, useMemo, useCallback } from 'react';
import {
    XCircle,
    TrendingUp,
    TrendingDown,
    Activity,
    CalendarDays,
    ChevronLeft,
    ChevronRight,
    Plus,
    Trash2,
    PartyPopper,
    Clock,
    Sparkles,
} from 'lucide-react';
import Card from '../../components/ui/Card';
import FormatNumber from '../../components/ui/FormatNumber';
import Button from '../../components/ui/Button';
import { Transaction, Employee } from '../../types';
import { getThaiPublicHolidayMap } from '../../utils';

/** บันทึกปฏิทิน — แยกจาก DailyLog เพื่อไม่ไปปนกับบันทึกงานประจำวัน */
export const CALENDAR_CATEGORY = 'Calendar' as const;
export type CalendarSubCategory = 'Holiday' | 'Appointment' | 'Reminder';

const isCalendarTx = (t: Transaction) => t.category === CALENDAR_CATEGORY;

const calendarKindLabel = (sub?: string) => {
    if (sub === 'Holiday') return 'วันหยุด';
    if (sub === 'Appointment') return 'นัดหมาย';
    if (sub === 'Reminder') return 'เหตุการณ์ / อื่นๆ';
    return sub || 'ปฏิทิน';
};

type CalendarViewProps = {
    transactions: Transaction[];
    employees: Employee[];
    onSaveTransaction: (t: Transaction) => void | Promise<void>;
    onDeleteTransaction?: (id: string) => void | Promise<void>;
};

const CalendarView = ({ transactions, employees, onSaveTransaction, onDeleteTransaction }: CalendarViewProps) => {
    const [selectedDay, setSelectedDay] = useState<string | null>(null);
    /** เดือนที่กำลังดู (วันที่ 1 ของเดือน) */
    const [cursorMonth, setCursorMonth] = useState(() => {
        const t = new Date();
        return new Date(t.getFullYear(), t.getMonth(), 1);
    });

    const [showAddModal, setShowAddModal] = useState(false);
    const [addPresetDate, setAddPresetDate] = useState<string>('');
    const [formKind, setFormKind] = useState<CalendarSubCategory>('Holiday');
    const [formTitle, setFormTitle] = useState('');
    const [formTime, setFormTime] = useState('');
    const [formNote, setFormNote] = useState('');

    const year = cursorMonth.getFullYear();
    const month = cursorMonth.getMonth();
    const daysInCurrentMonth = new Date(year, month + 1, 0).getDate();
    const monthLabel = cursorMonth.toLocaleDateString('th-TH', { month: 'long', year: 'numeric', timeZone: 'Asia/Bangkok' });

    const goPrevMonth = () => setCursorMonth(new Date(year, month - 1, 1));
    const goNextMonth = () => setCursorMonth(new Date(year, month + 1, 1));
    const goThisMonth = () => {
        const t = new Date();
        setCursorMonth(new Date(t.getFullYear(), t.getMonth(), 1));
    };

    const openAddModal = useCallback((dateStr?: string) => {
        setAddPresetDate(dateStr || selectedDay || new Date().toISOString().slice(0, 10));
        setFormKind('Holiday');
        setFormTitle('');
        setFormTime('');
        setFormNote('');
        setShowAddModal(true);
    }, [selectedDay]);

    const submitCalendarEntry = useCallback(async () => {
        const d = addPresetDate.slice(0, 10);
        if (!d || !formTitle.trim()) return;
        const id = `cal_${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
        const tx: Transaction = {
            id,
            date: d,
            type: 'Expense',
            category: CALENDAR_CATEGORY,
            subCategory: formKind,
            description: formTitle.trim(),
            amount: 0,
            note: formNote.trim() || undefined,
            eventTime: formTime.trim() || undefined,
        };
        await onSaveTransaction(tx);
        setShowAddModal(false);
    }, [addPresetDate, formTitle, formNote, formTime, formKind, onSaveTransaction]);

    const deleteCalendarEntry = useCallback(
        async (id: string) => {
            if (!onDeleteTransaction) return;
            if (!window.confirm('ลบรายการนี้จากปฏิทิน?')) return;
            await onDeleteTransaction(id);
        },
        [onDeleteTransaction]
    );

    const daysInMonth = useMemo(() => {
        const publicHolidayMap = getThaiPublicHolidayMap(year);
        return Array.from({ length: daysInCurrentMonth }, (_, i) => {
            const d = i + 1;
            const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;

            const dayTrans = transactions.filter((t) => (t.date || '').slice(0, 10) === dateStr);
            const financeTrans = dayTrans.filter((t) => !isCalendarTx(t));
            const inc = financeTrans.filter((t) => t.type === 'Income').reduce((s, t) => s + t.amount, 0);
            const exp = financeTrans.filter((t) => t.type === 'Expense').reduce((s, t) => s + t.amount, 0);

            const workingEmpIds = new Set(
                financeTrans.filter((t) => t.category === 'Labor' && (t.laborStatus === 'Work' || t.laborStatus === 'OT')).flatMap((t) => t.employeeIds || [])
            );
            const leaveTrans = financeTrans.filter(
                (t) => t.category === 'Labor' && (t.laborStatus === 'Leave' || t.laborStatus === 'Sick' || t.laborStatus === 'Personal')
            );
            const leaveEmpIds = new Set(leaveTrans.flatMap((t) => t.employeeIds || []));

            const leaveNames = Array.from(leaveEmpIds).map((id) => {
                const emp = employees.find((e) => e.id === id);
                return emp ? emp.nickname || emp.name : 'Unknown';
            });

            const presentCount = workingEmpIds.size;
            const leaveCount = leaveEmpIds.size;
            const missingCount = Math.max(0, employees.length - presentCount - leaveCount);

            const machineLogs = financeTrans.filter(
                (t) => t.category === 'DailyLog' && (t.subCategory === 'MachineWork' || t.subCategory === 'VehicleTrip')
            );
            const sandLogs = financeTrans.filter((t) => t.category === 'DailyLog' && t.subCategory === 'Sand');
            const eventLogs = financeTrans.filter((t) => t.category === 'DailyLog' && t.subCategory === 'Event');

            const calendarRows = dayTrans.filter(isCalendarTx);
            const autoHoliday = publicHolidayMap[dateStr]
                ? {
                      id: `${publicHolidayMap[dateStr].id}_auto`,
                      date: dateStr,
                      type: 'Expense' as const,
                      category: CALENDAR_CATEGORY,
                      subCategory: 'Holiday' as const,
                      description: publicHolidayMap[dateStr].name,
                      amount: 0,
                      note: 'วันหยุดนักขัตฤกษ์ (ระบบ)',
                  }
                : null;
            const allCalendarRows = autoHoliday ? [autoHoliday, ...calendarRows] : calendarRows;

            return {
                day: d,
                inc,
                exp,
                net: inc - exp,
                date: dateStr,
                presentCount,
                leaveCount,
                missingCount,
                transactions: dayTrans,
                financeTransactions: financeTrans,
                leaveNames,
                machineLogs,
                sandLogs,
                eventLogs,
                calendarRows: allCalendarRows,
            };
        });
    }, [transactions, employees, year, month, daysInCurrentMonth]);

    const monthIncome = daysInMonth.reduce((s, d) => s + d.inc, 0);
    const monthExpense = daysInMonth.reduce((s, d) => s + d.exp, 0);

    const HOLIDAY_TEMPLATES = ['วันหยุดนักขัตฤกษ์', 'หยุดบริษัท', 'หยุดชดเชย', 'วันหยุดพิเศษ'];
    const APPT_TEMPLATES = ['นัดลูกค้า', 'นัดซ่อมเครื่อง', 'ส่งมอบงาน', 'ประชุม'];

    return (
        <Card className="p-4 sm:p-6 lg:p-8 animate-fade-in relative z-10 bg-white border-slate-200 shadow-sm dark:bg-white/[0.02] dark:border-white/10">
            {/* Header & Monthly Summary */}
            <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center mb-6 sm:mb-8 gap-6">
                <div className="min-w-0">
                    <h3 className="font-bold text-2xl lg:text-3xl text-slate-800 dark:text-white flex items-center gap-3 flex-wrap">
                        <CalendarDays className="text-indigo-500 shrink-0" />
                        ปฏิทินการทำงาน <span className="text-slate-400 dark:text-slate-500 font-normal">(V.3)</span>
                    </h3>
                    <p className="text-sm text-slate-500 dark:text-slate-400 mt-2">
                        ภาพรวมรายรับรายจ่าย การมาทำงาน — เพิ่มวันหยุดและนัดหมายได้
                    </p>
                </div>

                <div className="flex flex-col sm:flex-row gap-3 w-full lg:w-auto items-stretch sm:items-center">
                    <div className="flex items-center gap-1 rounded-xl border border-slate-200 dark:border-white/10 bg-slate-50 dark:bg-white/[0.04] p-1">
                        <button
                            type="button"
                            onClick={goPrevMonth}
                            className="p-2 rounded-lg hover:bg-white dark:hover:bg-white/10 text-slate-600 dark:text-slate-300"
                            aria-label="เดือนก่อน"
                        >
                            <ChevronLeft size={20} />
                        </button>
                        <span className="px-2 sm:px-3 text-sm font-semibold text-slate-800 dark:text-slate-100 min-w-[8rem] text-center">{monthLabel}</span>
                        <button
                            type="button"
                            onClick={goNextMonth}
                            className="p-2 rounded-lg hover:bg-white dark:hover:bg-white/10 text-slate-600 dark:text-slate-300"
                            aria-label="เดือนถัดไป"
                        >
                            <ChevronRight size={20} />
                        </button>
                        <button
                            type="button"
                            onClick={goThisMonth}
                            className="ml-1 text-xs px-2 py-1.5 rounded-lg bg-indigo-100 dark:bg-indigo-500/20 text-indigo-700 dark:text-indigo-300 font-medium"
                        >
                            เดือนนี้
                        </button>
                    </div>
                    <Button type="button" onClick={() => openAddModal()} className="flex items-center justify-center gap-2 shrink-0">
                        <Plus size={18} /> เพิ่มวันหยุด / นัดหมาย
                    </Button>
                </div>

                <div className="flex gap-4 w-full lg:w-auto">
                    <div className="flex-1 lg:flex-none bg-emerald-50 dark:bg-emerald-500/10 border border-emerald-200 dark:border-emerald-500/25 px-4 py-3 rounded-2xl flex items-center gap-3 shadow-sm">
                        <div className="w-10 h-10 rounded-full bg-emerald-100 dark:bg-emerald-500/20 text-emerald-600 flex items-center justify-center shrink-0">
                            <TrendingUp size={20} />
                        </div>
                        <div>
                            <p className="text-xs text-emerald-600 dark:text-emerald-400 font-medium">รายรับเดือนนี้</p>
                            <p className="font-bold text-lg text-emerald-700 dark:text-emerald-300">
                                ฿<FormatNumber value={monthIncome} />
                            </p>
                        </div>
                    </div>
                    <div className="flex-1 lg:flex-none bg-red-50 dark:bg-rose-500/10 border border-red-200 dark:border-rose-500/25 px-4 py-3 rounded-2xl flex items-center gap-3 shadow-sm">
                        <div className="w-10 h-10 rounded-full bg-red-100 dark:bg-rose-500/20 text-red-600 flex items-center justify-center shrink-0">
                            <TrendingDown size={20} />
                        </div>
                        <div>
                            <p className="text-xs text-red-600 dark:text-rose-400 font-medium">รายจ่ายเดือนนี้</p>
                            <p className="font-bold text-lg text-red-700 dark:text-rose-300">
                                ฿<FormatNumber value={monthExpense} />
                            </p>
                        </div>
                    </div>
                </div>
            </div>

            {/* Legend */}
            <div className="flex flex-wrap gap-3 mb-4 text-xs text-slate-600 dark:text-slate-400">
                <span className="inline-flex items-center gap-1.5">
                    <PartyPopper size={14} className="text-rose-500" /> วันหยุด
                </span>
                <span className="inline-flex items-center gap-1.5">
                    <Clock size={14} className="text-violet-500" /> นัดหมาย
                </span>
                <span className="inline-flex items-center gap-1.5">
                    <Sparkles size={14} className="text-amber-500" /> เหตุการณ์ / อื่นๆ
                </span>
            </div>

            {/* Calendar Grid */}
            <div className="overflow-x-auto pb-4">
                <div className="grid grid-cols-7 gap-2 lg:gap-3 mb-3 text-center text-sm font-bold text-slate-400 dark:text-slate-500 min-w-[500px]">
                    {['อาทิตย์', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัส', 'ศุกร์', 'เสาร์'].map((d, i) => (
                        <div key={i}>{d}</div>
                    ))}
                </div>
                <div className="grid grid-cols-7 gap-2 lg:gap-3 min-w-[500px]">
                    {Array.from({ length: new Date(year, month, 1).getDay() }, (_, i) => (
                        <div key={`empty-${i}`} className="aspect-[4/3] sm:aspect-square rounded-2xl bg-slate-50/50 dark:bg-white/[0.03] border border-slate-100 dark:border-white/10" />
                    ))}
                    {daysInMonth.map((d, i) => {
                        let bgClass = 'bg-white dark:bg-white/[0.03] border-slate-200 dark:border-white/10 hover:shadow-lg';
                        if (d.inc > 0 || d.exp > 0) {
                            if (d.net > 0) bgClass = 'bg-emerald-50 dark:bg-emerald-500/10 border-emerald-200 dark:border-emerald-500/25 hover:shadow-emerald-100';
                            else if (d.net < 0) bgClass = 'bg-rose-50 dark:bg-rose-500/10 border-rose-200 dark:border-rose-500/25 hover:shadow-rose-100';
                            else bgClass = 'bg-amber-50 dark:bg-amber-500/10 border-amber-200 dark:border-amber-500/25 hover:shadow-amber-100';
                        }
                        const hasHol = d.calendarRows.some((t) => t.subCategory === 'Holiday');
                        const hasApt = d.calendarRows.some((t) => t.subCategory === 'Appointment');
                        const hasRem = d.calendarRows.some((t) => t.subCategory === 'Reminder');

                        return (
                            <div
                                key={i}
                                onClick={() => setSelectedDay(d.date)}
                                className={`aspect-[4/3] sm:aspect-square border rounded-2xl p-2 sm:p-3 flex flex-col justify-between transition-all duration-300 hover:-translate-y-1 hover:shadow-xl cursor-pointer relative group ${bgClass}`}
                            >
                                <div className="flex justify-between items-start gap-1">
                                    <span
                                        className={`text-sm sm:text-base font-bold ${
                                            d.inc > 0 || d.exp > 0 ? (d.net > 0 ? 'text-emerald-700 dark:text-emerald-300' : 'text-rose-700 dark:text-rose-300') : 'text-slate-400 dark:text-slate-500'
                                        }`}
                                    >
                                        {d.day}
                                    </span>
                                    <div className="flex flex-wrap gap-1 justify-end">
                                        {hasHol && (
                                            <span className="text-[9px] font-bold px-1 py-0.5 rounded bg-rose-100 dark:bg-rose-500/30 text-rose-700 dark:text-rose-200" title="มีวันหยุด">
                                                หยุด
                                            </span>
                                        )}
                                        {hasApt && (
                                            <span className="text-[9px] font-bold px-1 py-0.5 rounded bg-violet-100 dark:bg-violet-500/30 text-violet-700 dark:text-violet-200" title="มีนัดหมาย">
                                                นัด
                                            </span>
                                        )}
                                        {hasRem && (
                                            <span className="text-[9px] font-bold px-1 py-0.5 rounded bg-amber-100 dark:bg-amber-500/30 text-amber-800 dark:text-amber-200" title="มีเหตุการณ์">
                                                !
                                            </span>
                                        )}
                                        {d.presentCount > 0 && (
                                            <div
                                                className="w-2 h-2 rounded-full bg-blue-500 shadow-[0_0_5px_rgba(59,130,246,0.5)]"
                                                title={`มา: ${d.presentCount}`}
                                            />
                                        )}
                                        {d.leaveCount > 0 && (
                                            <div
                                                className="w-2 h-2 rounded-full bg-amber-500 shadow-[0_0_5px_rgba(245,158,11,0.5)]"
                                                title={`ลา: ${d.leaveCount}`}
                                            />
                                        )}
                                    </div>
                                </div>

                                <div className="hidden md:flex flex-col gap-1 mt-1 overflow-hidden min-h-0">
                                    {d.calendarRows.slice(0, 2).map((t) => (
                                        <span
                                            key={t.id}
                                            className={`text-[9px] px-1 py-0.5 rounded truncate font-medium ${
                                                t.subCategory === 'Holiday'
                                                    ? 'bg-rose-100 text-rose-800 dark:bg-rose-500/20 dark:text-rose-200'
                                                    : t.subCategory === 'Appointment'
                                                      ? 'bg-violet-100 text-violet-800 dark:bg-violet-500/20 dark:text-violet-200'
                                                      : 'bg-amber-100 text-amber-800 dark:bg-amber-500/20 dark:text-amber-200'
                                            }`}
                                            title={t.description}
                                        >
                                            {t.subCategory === 'Holiday' ? '🎌' : t.subCategory === 'Appointment' ? '📅' : '✨'} {t.description}
                                        </span>
                                    ))}
                                    {d.calendarRows.length > 2 && <span className="text-[9px] text-slate-400 pl-1">+{d.calendarRows.length - 2}</span>}
                                    {d.leaveNames.slice(0, 2).map((name, idx) => (
                                        <span key={idx} className="text-[10px] bg-amber-100 dark:bg-amber-500/20 text-amber-700 dark:text-amber-300 px-1.5 py-0.5 rounded truncate font-medium">
                                            ลา: {name}
                                        </span>
                                    ))}
                                    {d.leaveNames.length > 2 && <span className="text-[10px] text-amber-500 pl-1">+{d.leaveNames.length - 2}</span>}
                                </div>

                                <div className="flex flex-col gap-1 text-[10px] sm:text-xs text-right mt-auto">
                                    {d.inc > 0 && (
                                        <span className="text-emerald-600 dark:text-emerald-400 font-bold bg-emerald-100 dark:bg-emerald-500/20 px-1 rounded inline-block self-end">
                                            +<FormatNumber value={d.inc} />
                                        </span>
                                    )}
                                    {d.exp > 0 && (
                                        <span className="text-rose-500 dark:text-rose-400 font-bold bg-rose-100 dark:bg-rose-500/20 px-1 rounded inline-block self-end">
                                            -<FormatNumber value={d.exp} />
                                        </span>
                                    )}
                                </div>

                                <button
                                    type="button"
                                    onClick={(e) => {
                                        e.stopPropagation();
                                        openAddModal(d.date);
                                    }}
                                    className="absolute bottom-1 right-1 opacity-0 group-hover:opacity-100 p-1 rounded-lg bg-indigo-100 dark:bg-indigo-500/30 text-indigo-600 dark:text-indigo-300 transition-opacity"
                                    title="เพิ่มวันหยุด/นัดหมาย"
                                >
                                    <Plus size={14} />
                                </button>
                            </div>
                        );
                    })}
                </div>
            </div>

            {/* Add modal */}
            {showAddModal && (
                <div className="fixed inset-0 z-[120] flex items-center justify-center p-4">
                    <div className="absolute inset-0 bg-slate-900/50 backdrop-blur-sm" onClick={() => setShowAddModal(false)} />
                    <div className="relative w-full max-w-md bg-white dark:bg-[#141824] border border-slate-200 dark:border-white/10 rounded-2xl shadow-2xl p-5 sm:p-6 animate-slide-up">
                        <h4 className="font-bold text-lg text-slate-800 dark:text-white mb-4 flex items-center gap-2">
                            <Plus size={20} className="text-indigo-500" /> เพิ่มในปฏิทิน
                        </h4>
                        <div className="space-y-3">
                            <div>
                                <label className="text-xs font-medium text-slate-600 dark:text-slate-400">ประเภท</label>
                                <select
                                    value={formKind}
                                    onChange={(e) => setFormKind(e.target.value as CalendarSubCategory)}
                                    className="mt-1 w-full rounded-xl border border-slate-200 dark:border-white/15 bg-white dark:bg-white/5 px-3 py-2 text-sm text-slate-800 dark:text-slate-200"
                                >
                                    <option value="Holiday">วันหยุด</option>
                                    <option value="Appointment">นัดหมาย / พบลูกค้า</option>
                                    <option value="Reminder">เหตุการณ์สำคัญ / อื่นๆ</option>
                                </select>
                            </div>
                            <div>
                                <label className="text-xs font-medium text-slate-600 dark:text-slate-400">วันที่</label>
                                <input
                                    type="date"
                                    value={addPresetDate}
                                    onChange={(e) => setAddPresetDate(e.target.value)}
                                    className="mt-1 w-full rounded-xl border border-slate-200 dark:border-white/15 bg-white dark:bg-white/5 px-3 py-2 text-sm"
                                />
                            </div>
                            <div>
                                <label className="text-xs font-medium text-slate-600 dark:text-slate-400">หัวข้อ</label>
                                <input
                                    type="text"
                                    value={formTitle}
                                    onChange={(e) => setFormTitle(e.target.value)}
                                    placeholder="เช่น หยุดสงกรานต์ / นัดส่งงานหน้างาน"
                                    className="mt-1 w-full rounded-xl border border-slate-200 dark:border-white/15 bg-white dark:bg-white/5 px-3 py-2 text-sm"
                                />
                            </div>
                            {(formKind === 'Appointment' || formKind === 'Reminder') && (
                                <div>
                                    <label className="text-xs font-medium text-slate-600 dark:text-slate-400">เวลา (ไม่บังคับ)</label>
                                    <input
                                        type="time"
                                        value={formTime}
                                        onChange={(e) => setFormTime(e.target.value)}
                                        className="mt-1 w-full rounded-xl border border-slate-200 dark:border-white/15 bg-white dark:bg-white/5 px-3 py-2 text-sm"
                                    />
                                </div>
                            )}
                            <div>
                                <label className="text-xs font-medium text-slate-600 dark:text-slate-400">รายละเอียด (ไม่บังคับ)</label>
                                <textarea
                                    value={formNote}
                                    onChange={(e) => setFormNote(e.target.value)}
                                    rows={2}
                                    className="mt-1 w-full rounded-xl border border-slate-200 dark:border-white/15 bg-white dark:bg-white/5 px-3 py-2 text-sm resize-none"
                                />
                            </div>
                            <div>
                                <p className="text-[10px] text-slate-500 mb-1">แม่แบบข้อความ</p>
                                <div className="flex flex-wrap gap-1.5">
                                    {(formKind === 'Holiday' ? HOLIDAY_TEMPLATES : APPT_TEMPLATES).map((tpl) => (
                                        <button
                                            key={tpl}
                                            type="button"
                                            onClick={() => setFormTitle(tpl)}
                                            className="text-[10px] px-2 py-1 rounded-lg bg-slate-100 dark:bg-white/10 hover:bg-indigo-100 dark:hover:bg-indigo-500/20 text-slate-700 dark:text-slate-300"
                                        >
                                            {tpl}
                                        </button>
                                    ))}
                                </div>
                            </div>
                        </div>
                        <div className="flex gap-2 justify-end mt-6">
                            <Button type="button" variant="outline" onClick={() => setShowAddModal(false)}>
                                ยกเลิก
                            </Button>
                            <Button type="button" onClick={() => void submitCalendarEntry()} disabled={!formTitle.trim()}>
                                บันทึก
                            </Button>
                        </div>
                    </div>
                </div>
            )}

            {/* Day detail modal */}
            {selectedDay &&
                (() => {
                    const dayDetails = daysInMonth.find((d) => d.date === selectedDay);
                    if (!dayDetails) return null;

                    const dayDate = new Date(selectedDay + 'T12:00:00+07:00');

                    return (
                        <div className="fixed inset-0 z-[110] flex items-center justify-center p-4 sm:p-6 animate-fade-in">
                            <div className="absolute inset-0 bg-slate-900/40 backdrop-blur-sm" onClick={() => setSelectedDay(null)} />

                            <div className="w-full max-w-3xl bg-white dark:bg-[#141824] border border-slate-200 dark:border-white/10 rounded-3xl shadow-2xl relative z-10 max-h-[90vh] flex flex-col overflow-hidden animate-slide-up">
                                <div className="p-6 sm:p-8 flex justify-between items-center border-b border-slate-100 dark:border-white/10 bg-slate-50 dark:bg-white/[0.03]">
                                    <div className="min-w-0">
                                        <h3 className="font-bold text-2xl sm:text-3xl text-slate-800 dark:text-white break-words">
                                            {dayDate.toLocaleDateString('th-TH', { timeZone: 'Asia/Bangkok', weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}
                                        </h3>
                                        <p className="text-slate-500 dark:text-slate-400 mt-1 flex items-center gap-2 text-sm">
                                            <Activity size={16} /> สรุปกิจกรรมและข้อมูลการเงิน
                                        </p>
                                    </div>
                                    <div className="flex items-center gap-2 shrink-0">
                                        <Button type="button" className="!py-2 !px-3 text-sm" onClick={() => openAddModal(selectedDay)}>
                                            <Plus size={16} className="inline mr-1" /> เพิ่ม
                                        </Button>
                                        <button
                                            onClick={() => setSelectedDay(null)}
                                            className="w-10 h-10 rounded-full bg-slate-100 dark:bg-white/10 flex items-center justify-center text-slate-500 hover:bg-slate-200 dark:hover:bg-white/20 transition-colors"
                                        >
                                            <XCircle size={24} />
                                        </button>
                                    </div>
                                </div>

                                <div className="p-6 sm:p-8 overflow-y-auto space-y-8">
                                    {/* ปฏิทิน: วันหยุด / นัดหมาย */}
                                    {dayDetails.calendarRows.length > 0 && (
                                        <div>
                                            <h4 className="font-bold text-lg text-slate-700 dark:text-slate-200 mb-3 flex items-center gap-2">
                                                <CalendarDays size={18} className="text-indigo-500" />
                                                วันหยุด / นัดหมาย / เหตุการณ์
                                            </h4>
                                            <div className="space-y-2">
                                                {dayDetails.calendarRows.map((t) => (
                                                    <div
                                                        key={t.id}
                                                        className="flex items-start justify-between gap-3 p-4 rounded-2xl border border-slate-200 dark:border-white/10 bg-slate-50/80 dark:bg-white/[0.04]"
                                                    >
                                                        <div className="min-w-0">
                                                            <span
                                                                className={`text-[10px] font-bold px-2 py-0.5 rounded-md ${
                                                                    t.subCategory === 'Holiday'
                                                                        ? 'bg-rose-100 text-rose-800 dark:bg-rose-500/25 dark:text-rose-200'
                                                                        : t.subCategory === 'Appointment'
                                                                          ? 'bg-violet-100 text-violet-800 dark:bg-violet-500/25 dark:text-violet-200'
                                                                          : 'bg-amber-100 text-amber-800 dark:bg-amber-500/25 dark:text-amber-200'
                                                                }`}
                                                            >
                                                                {calendarKindLabel(t.subCategory)}
                                                            </span>
                                                            <p className="font-semibold text-slate-800 dark:text-slate-100 mt-1">{t.description}</p>
                                                            {t.eventTime && (
                                                                <p className="text-sm text-violet-600 dark:text-violet-400 flex items-center gap-1 mt-1">
                                                                    <Clock size={14} /> {t.eventTime} น.
                                                                </p>
                                                            )}
                                                            {t.note && <p className="text-sm text-slate-600 dark:text-slate-400 mt-1">{t.note}</p>}
                                                        </div>
                                                        {onDeleteTransaction && (
                                                            <button
                                                                type="button"
                                                                onClick={() => void deleteCalendarEntry(t.id)}
                                                                className="p-2 rounded-xl text-slate-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-500/10 shrink-0"
                                                                title="ลบ"
                                                            >
                                                                <Trash2 size={18} />
                                                            </button>
                                                        )}
                                                    </div>
                                                ))}
                                            </div>
                                        </div>
                                    )}

                                    <div className="grid grid-cols-3 gap-4">
                                        <div className="bg-emerald-50 dark:bg-emerald-500/10 p-4 rounded-2xl border border-emerald-200 dark:border-emerald-500/25 text-center">
                                            <p className="text-sm text-emerald-600 dark:text-emerald-400 mb-1">รายรับ</p>
                                            <p className="font-bold text-xl sm:text-2xl text-emerald-700 dark:text-emerald-300">
                                                +<FormatNumber value={dayDetails.inc} />
                                            </p>
                                        </div>
                                        <div className="bg-rose-50 dark:bg-rose-500/10 p-4 rounded-2xl border border-rose-200 dark:border-rose-500/25 text-center">
                                            <p className="text-sm text-rose-600 dark:text-rose-400 mb-1">รายจ่าย</p>
                                            <p className="font-bold text-xl sm:text-2xl text-rose-700 dark:text-rose-300">
                                                -<FormatNumber value={dayDetails.exp} />
                                            </p>
                                        </div>
                                        <div
                                            className={`p-4 rounded-2xl border text-center ${
                                                dayDetails.net >= 0
                                                    ? 'bg-indigo-50 dark:bg-indigo-500/10 border-indigo-200 dark:border-indigo-500/25 text-indigo-700 dark:text-indigo-300'
                                                    : 'bg-orange-50 dark:bg-orange-500/10 border-orange-200 dark:border-orange-500/25 text-orange-700 dark:text-orange-300'
                                            }`}
                                        >
                                            <p className="text-sm mb-1 opacity-80">ยอดสุทธิ</p>
                                            <p className="font-bold text-xl sm:text-2xl">
                                                {dayDetails.net > 0 ? '+' : ''}
                                                <FormatNumber value={dayDetails.net} />
                                            </p>
                                        </div>
                                    </div>

                                    <div>
                                        <h4 className="font-bold text-lg text-slate-700 dark:text-slate-200 mb-4 flex items-center gap-2">
                                            <span className="w-2 h-6 bg-blue-500 rounded-full" />
                                            การมาทำงาน
                                        </h4>
                                        <div className="grid grid-cols-2 gap-4">
                                            <div className="flex items-center gap-4 bg-white dark:bg-white/[0.03] p-4 rounded-2xl border border-slate-200 dark:border-white/10 shadow-sm">
                                                <div className="w-12 h-12 rounded-full bg-blue-100 dark:bg-blue-500/20 text-blue-600 flex items-center justify-center text-xl font-bold">
                                                    {dayDetails.presentCount}
                                                </div>
                                                <div>
                                                    <p className="font-bold text-slate-800 dark:text-slate-100">มาทำงาน</p>
                                                    <p className="text-sm text-slate-500 dark:text-slate-400">พนักงานเข้ากะ</p>
                                                </div>
                                            </div>
                                            <div className="flex items-center gap-4 bg-white dark:bg-white/[0.03] p-4 rounded-2xl border border-slate-200 dark:border-white/10 shadow-sm">
                                                <div className="w-12 h-12 rounded-full bg-amber-100 dark:bg-amber-500/20 text-amber-600 flex items-center justify-center text-xl font-bold">
                                                    {dayDetails.leaveCount}
                                                </div>
                                                <div className="min-w-0">
                                                    <p className="font-bold text-slate-800 dark:text-slate-100">ลางาน</p>
                                                    <p className="text-sm text-slate-500 dark:text-slate-400 break-words">{dayDetails.leaveNames.join(', ') || '-'}</p>
                                                </div>
                                            </div>
                                        </div>
                                    </div>

                                    <div>
                                        <h4 className="font-bold text-lg text-slate-700 dark:text-slate-200 mb-4 flex items-center gap-2">
                                            <span className="w-2 h-6 bg-purple-500 rounded-full" />
                                            บันทึกกิจกรรมแทรกเตอร์ / ทราย
                                        </h4>

                                        <div className="space-y-3">
                                            {(dayDetails.machineLogs || []).map((t) => (
                                                <div key={t.id} className="flex gap-4 p-4 border border-slate-200 dark:border-white/10 rounded-2xl bg-white dark:bg-white/[0.03] shadow-sm hover:shadow-md transition-shadow">
                                                    <div className="w-12 h-12 rounded-2xl bg-orange-100 dark:bg-orange-500/20 flex items-center justify-center text-2xl shrink-0">
                                                        🚜
                                                    </div>
                                                    <div className="flex-1 min-w-0">
                                                        {t.subCategory === 'VehicleTrip' ? (
                                                            <>
                                                                <div className="font-bold text-slate-800 dark:text-slate-100">{t.description || 'เที่ยวรถ'}</div>
                                                                {t.workDetails && <div className="text-slate-600 dark:text-slate-400 mt-1">{t.workDetails}</div>}
                                                                {t.amount > 0 && <div className="text-amber-600 font-medium mt-1">฿{t.amount.toLocaleString()}</div>}
                                                            </>
                                                        ) : (
                                                            <>
                                                                <div className="font-bold text-lg text-slate-800 dark:text-slate-100">
                                                                    {t.machineId || 'เครื่องจักร'}{' '}
                                                                    <span className="text-orange-500 font-medium">({t.machineHours ?? 0} ชม.)</span>
                                                                </div>
                                                                <div className="text-slate-600 dark:text-slate-400 mt-1">{t.note || t.description}</div>
                                                                {t.location && (
                                                                    <div className="text-sm text-slate-400 dark:text-slate-500 mt-2 flex items-center gap-1">📍 {t.location}</div>
                                                                )}
                                                            </>
                                                        )}
                                                    </div>
                                                </div>
                                            ))}

                                            {(dayDetails.sandLogs || []).map((t) => (
                                                <div key={t.id} className="flex gap-4 p-4 border border-slate-200 dark:border-white/10 rounded-2xl bg-white dark:bg-white/[0.03] shadow-sm hover:shadow-md transition-shadow">
                                                    <div className="w-12 h-12 rounded-2xl bg-cyan-100 dark:bg-cyan-500/20 flex items-center justify-center text-2xl shrink-0">
                                                        🌊
                                                    </div>
                                                    <div className="flex-1 min-w-0">
                                                        <div className="flex justify-between items-start gap-2">
                                                            <div className="font-bold text-lg text-slate-800 dark:text-slate-100">
                                                                ล้างทราย{' '}
                                                                <span className="text-cyan-600 font-medium">{(t.sandMorning || 0) + (t.sandAfternoon || 0)} คิว</span>
                                                            </div>
                                                            <span className="text-xs font-bold px-2 py-1 rounded bg-slate-100 dark:bg-white/10 text-slate-600 dark:text-slate-400 shrink-0">
                                                                {t.sandMachineType === 'Old' ? 'เครื่องเก่า' : t.sandMachineType === 'New' ? 'เครื่องใหม่' : '-'}
                                                            </span>
                                                        </div>
                                                        <div className="text-slate-600 dark:text-slate-400 mt-1">
                                                            เช้า: {t.sandMorning ?? 0} คิว / บ่าย: {t.sandAfternoon ?? 0} คิว
                                                        </div>
                                                        {t.sandTransport != null && t.sandTransport > 0 && (
                                                            <div className="text-slate-500 dark:text-slate-500 text-sm mt-1">🚛 ขน: {t.sandTransport} คิว</div>
                                                        )}
                                                        {t.amount > 0 && <div className="text-slate-500 text-sm mt-1">฿{t.amount.toLocaleString()}</div>}
                                                    </div>
                                                </div>
                                            ))}

                                            {(dayDetails.eventLogs || []).map((t) => (
                                                <div key={t.id} className="flex gap-4 p-4 border border-orange-100 dark:border-orange-500/20 rounded-2xl bg-amber-50/50 dark:bg-amber-500/10 shadow-sm">
                                                    <div className="w-12 h-12 rounded-2xl bg-amber-100 dark:bg-amber-500/20 flex items-center justify-center text-2xl shrink-0">
                                                        📌
                                                    </div>
                                                    <div className="font-medium text-slate-800 dark:text-slate-100">{t.description}</div>
                                                </div>
                                            ))}

                                            {!(dayDetails.machineLogs?.length || 0) &&
                                                !(dayDetails.sandLogs?.length || 0) &&
                                                !(dayDetails.eventLogs?.length || 0) && (
                                                    <div className="text-center bg-slate-50 dark:bg-white/[0.03] border border-dashed border-slate-200 dark:border-white/10 rounded-2xl p-8 text-slate-400 dark:text-slate-500">
                                                        ไม่มีบันทึกกิจกรรมพิเศษสำหรับวันนี้
                                                    </div>
                                                )}
                                        </div>
                                    </div>

                                    <div>
                                        <h4 className="font-bold text-lg text-slate-700 dark:text-slate-200 mb-4 flex items-center gap-2">
                                            <span className="w-2 h-6 bg-emerald-500 rounded-full" />
                                            รายการเดินบัญชี (ไม่รวมรายการปฏิทิน)
                                        </h4>

                                        <div className="space-y-3">
                                            {(dayDetails.financeTransactions || []).map((t) => (
                                                <div
                                                    key={t.id}
                                                    className="group p-4 bg-white dark:bg-white/[0.03] border border-slate-200 dark:border-white/10 rounded-2xl shadow-sm hover:shadow-md transition-all flex justify-between items-center gap-3"
                                                >
                                                    <div className="flex items-center gap-4 min-w-0">
                                                        <div
                                                            className={`w-10 h-10 rounded-full flex items-center justify-center font-bold shrink-0 ${
                                                                t.type === 'Income' ? 'bg-emerald-100 dark:bg-emerald-500/20 text-emerald-600' : 'bg-rose-100 dark:bg-rose-500/20 text-rose-600'
                                                            }`}
                                                        >
                                                            {t.type === 'Income' ? '+' : '-'}
                                                        </div>
                                                        <div className="min-w-0">
                                                            <p className="font-bold text-slate-800 dark:text-slate-100 line-clamp-2">{t.description}</p>
                                                            <p className="text-sm text-slate-500 dark:text-slate-400">
                                                                {t.category} {t.subCategory ? `• ${t.subCategory}` : ''}
                                                            </p>
                                                        </div>
                                                    </div>
                                                    <div
                                                        className={`font-bold text-lg shrink-0 ${
                                                            t.type === 'Income' ? 'text-emerald-600' : t.category === 'Leave' ? 'text-amber-500' : 'text-rose-500'
                                                        }`}
                                                    >
                                                        {t.amount > 0 ? (
                                                            <>
                                                                ฿<FormatNumber value={t.amount} />
                                                            </>
                                                        ) : t.category === 'Leave' ? (
                                                            'ลา'
                                                        ) : (
                                                            '-'
                                                        )}
                                                    </div>
                                                </div>
                                            ))}

                                            {dayDetails.financeTransactions?.length === 0 && (
                                                <div className="text-center p-6 text-slate-400 dark:text-slate-500 italic">ไม่มีรายการเดินบัญชี</div>
                                            )}
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    );
                })()}
        </Card>
    );
};

export default CalendarView;
