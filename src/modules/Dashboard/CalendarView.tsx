import { useState } from 'react';
import { XCircle, TrendingUp, TrendingDown, Activity, CalendarDays } from 'lucide-react';
import Card from '../../components/ui/Card';
import FormatNumber from '../../components/ui/FormatNumber';
import { Transaction, Employee } from '../../types';

const CalendarView = ({ transactions, employees }: { transactions: Transaction[], employees: Employee[] }) => {
    const [selectedDay, setSelectedDay] = useState<string | null>(null);

    // จำนวนวันจริงในเดือนปัจจุบัน
    const today = new Date();
    const year = today.getFullYear();
    const month = today.getMonth();
    const daysInCurrentMonth = new Date(year, month + 1, 0).getDate();

    const daysInMonth = Array.from({ length: daysInCurrentMonth }, (_, i) => {
        const d = i + 1;
        const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;

        const dayTrans = transactions.filter(t => (t.date || '').slice(0, 10) === dateStr);
        const inc = dayTrans.filter(t => t.type === 'Income').reduce((s, t) => s + t.amount, 0);
        const exp = dayTrans.filter(t => t.type === 'Expense').reduce((s, t) => s + t.amount, 0);

        // การมาทำงาน: Labor ที่ laborStatus = Work หรือ OT = มา, Leave/Sick/Personal = ลา
        const workingEmpIds = new Set(dayTrans.filter(t => t.category === 'Labor' && (t.laborStatus === 'Work' || t.laborStatus === 'OT')).flatMap(t => t.employeeIds || []));
        const leaveTrans = dayTrans.filter(t => t.category === 'Labor' && (t.laborStatus === 'Leave' || t.laborStatus === 'Sick' || t.laborStatus === 'Personal'));
        const leaveEmpIds = new Set(leaveTrans.flatMap(t => t.employeeIds || []));

        const leaveNames = Array.from(leaveEmpIds).map(id => {
            const emp = employees.find(e => e.id === id);
            return emp ? (emp.nickname || emp.name) : 'Unknown';
        });

        const presentCount = workingEmpIds.size;
        const leaveCount = leaveEmpIds.size;
        const missingCount = Math.max(0, employees.length - presentCount - leaveCount);

        // บันทึกประจำวัน: ใช้ subCategory ตามที่ระบบบันทึก (Sand, VehicleTrip, Event)
        const machineLogs = dayTrans.filter(t => t.category === 'DailyLog' && (t.subCategory === 'MachineWork' || t.subCategory === 'VehicleTrip'));
        const sandLogs = dayTrans.filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand');
        const eventLogs = dayTrans.filter(t => t.category === 'DailyLog' && t.subCategory === 'Event');

        return { day: d, inc, exp, net: inc - exp, date: dateStr, presentCount, leaveCount, missingCount, transactions: dayTrans, leaveNames, machineLogs, sandLogs, eventLogs };
    });

    const monthIncome = daysInMonth.reduce((s, d) => s + d.inc, 0);
    const monthExpense = daysInMonth.reduce((s, d) => s + d.exp, 0);

    return (
        <Card className="p-4 sm:p-6 lg:p-8 animate-fade-in relative z-10 bg-white border-slate-200 shadow-sm">
            {/* Header & Monthly Summary */}
            <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center mb-8 gap-6">
                <div>
                    <h3 className="font-bold text-2xl lg:text-3xl text-slate-800 flex items-center gap-3">
                        <CalendarDays className="text-indigo-500" />
                        ปฏิทินการทำงาน <span className="text-slate-400 font-normal">เดือนนี้</span>
                    </h3>
                    <p className="text-sm text-slate-500 mt-2">ภาพรวมรายรับรายจ่าย และ การมาทำงานพนักงาน</p>
                </div>

                <div className="flex gap-4 w-full lg:w-auto">
                    <div className="flex-1 lg:flex-none bg-emerald-50 border border-emerald-200 px-4 py-3 rounded-2xl flex items-center gap-3 shadow-sm">
                        <div className="w-10 h-10 rounded-full bg-emerald-100 text-emerald-600 flex items-center justify-center shrink-0">
                            <TrendingUp size={20} />
                        </div>
                        <div>
                            <p className="text-xs text-emerald-600 font-medium">รายรับเดือนนี้</p>
                            <p className="font-bold text-lg text-emerald-700">฿<FormatNumber value={monthIncome} /></p>
                        </div>
                    </div>
                    <div className="flex-1 lg:flex-none bg-red-50 border border-red-200 px-4 py-3 rounded-2xl flex items-center gap-3 shadow-sm">
                        <div className="w-10 h-10 rounded-full bg-red-100 text-red-600 flex items-center justify-center shrink-0">
                            <TrendingDown size={20} />
                        </div>
                        <div>
                            <p className="text-xs text-red-600 font-medium">รายจ่ายเดือนนี้</p>
                            <p className="font-bold text-lg text-red-700">฿<FormatNumber value={monthExpense} /></p>
                        </div>
                    </div>
                </div>
            </div>

            {/* Calendar Grid — วันแรกของเดือนให้ตรงกับวันในสัปดาห์ */}
            <div className="overflow-x-auto pb-4">
                <div className="grid grid-cols-7 gap-2 lg:gap-3 mb-3 text-center text-sm font-bold text-slate-400 min-w-[500px]">
                    {['อาทิตย์', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัส', 'ศุกร์', 'เสาร์'].map((d, i) => <div key={i}>{d}</div>)}
                </div>
                <div className="grid grid-cols-7 gap-2 lg:gap-3 min-w-[500px]">
                    {Array.from({ length: new Date(year, month, 1).getDay() }, (_, i) => (
                        <div key={`empty-${i}`} className="aspect-[4/3] sm:aspect-square rounded-2xl bg-slate-50/50 border border-slate-100" />
                    ))}
                    {daysInMonth.map((d, i) => {
                        // Determine heatmap background
                        let bgClass = "bg-white border-slate-200 hover:shadow-lg";
                        if (d.inc > 0 || d.exp > 0) {
                            if (d.net > 0) bgClass = "bg-emerald-50 border-emerald-200 hover:shadow-emerald-100";
                            else if (d.net < 0) bgClass = "bg-rose-50 border-rose-200 hover:shadow-rose-100";
                            else bgClass = "bg-amber-50 border-amber-200 hover:shadow-amber-100";
                        }

                        return (
                            <div
                                key={i}
                                onClick={() => setSelectedDay(d.date)}
                                className={`aspect-[4/3] sm:aspect-square border rounded-2xl p-2 sm:p-3 flex flex-col justify-between transition-all duration-300 hover:-translate-y-1 hover:shadow-xl cursor-pointer relative group ${bgClass}`}
                            >
                                <div className="flex justify-between items-start">
                                    <span className={`text-sm sm:text-base font-bold ${d.inc > 0 || d.exp > 0 ? (d.net > 0 ? 'text-emerald-700' : 'text-rose-700') : 'text-slate-400'}`}>
                                        {d.day}
                                    </span>
                                    <div className="flex gap-1.5">
                                        {d.presentCount > 0 && <div className="w-2 h-2 rounded-full bg-blue-500 shadow-[0_0_5px_rgba(59,130,246,0.5)]" title={`มา: ${d.presentCount}`} />}
                                        {d.leaveCount > 0 && <div className="w-2 h-2 rounded-full bg-amber-500 shadow-[0_0_5px_rgba(245,158,11,0.5)]" title={`ลา: ${d.leaveCount}`} />}
                                    </div>
                                </div>

                                {/* Display Leave Names — hidden on tiny mobile screens */}
                                <div className="hidden md:flex flex-col gap-1 mt-2 overflow-hidden">
                                    {d.leaveNames.slice(0, 2).map((name, idx) => (
                                        <span key={idx} className="text-[10px] bg-amber-100 text-amber-700 px-1.5 py-0.5 rounded truncate font-medium">ลา: {name}</span>
                                    ))}
                                    {d.leaveNames.length > 2 && <span className="text-[10px] text-amber-500 pl-1">+{d.leaveNames.length - 2}</span>}
                                </div>

                                <div className="flex flex-col gap-1 text-[10px] sm:text-xs text-right mt-auto">
                                    {d.inc > 0 && <span className="text-emerald-600 font-bold bg-emerald-100 px-1 rounded inline-block self-end">+{FormatNumber({ value: d.inc })}</span>}
                                    {d.exp > 0 && <span className="text-rose-500 font-bold bg-rose-100 px-1 rounded inline-block self-end">-{FormatNumber({ value: d.exp })}</span>}
                                </div>
                            </div>
                        )
                    })}
                </div>
            </div>

            {/* Premium Glassmorphic Modal for Day Details */}
            {selectedDay && (() => {
                const dayDetails = daysInMonth.find(d => d.date === selectedDay);
                if (!dayDetails) return null;

                const dayDate = new Date(selectedDay);

                return (
                    <div className="fixed inset-0 z-[110] flex items-center justify-center p-4 sm:p-6 animate-fade-in">
                        {/* Backdrop */}
                        <div className="absolute inset-0 bg-slate-900/40 backdrop-blur-sm" onClick={() => setSelectedDay(null)} />

                        {/* Modal Content */}
                        <div className="w-full max-w-3xl bg-white border border-slate-200 rounded-3xl shadow-2xl relative z-10 max-h-[90vh] flex flex-col overflow-hidden animate-slide-up">

                            {/* Modal Header */}
                            <div className="p-6 sm:p-8 flex justify-between items-center border-b border-slate-100 bg-slate-50">
                                <div>
                                    <h3 className="font-bold text-2xl sm:text-3xl text-slate-800">
                                        {dayDate.toLocaleDateString('th-TH', { weekday: 'long', day: 'numeric', month: 'long' })}
                                    </h3>
                                    <p className="text-slate-500 mt-1 flex items-center gap-2">
                                        <Activity size={16} /> สรุปกิจกรรมและข้อมูลการเงิน
                                    </p>
                                </div>
                                <button onClick={() => setSelectedDay(null)} className="w-10 h-10 rounded-full bg-slate-100 flex items-center justify-center text-slate-500 hover:bg-slate-200 transition-colors">
                                    <XCircle size={24} />
                                </button>
                            </div>

                            {/* Modal Body */}
                            <div className="p-6 sm:p-8 overflow-y-auto space-y-8">

                                {/* Financial Summary */}
                                <div className="grid grid-cols-3 gap-4">
                                    <div className="bg-emerald-50 p-4 rounded-2xl border border-emerald-200 text-center">
                                        <p className="text-sm text-emerald-600 mb-1">รายรับ</p>
                                        <p className="font-bold text-xl sm:text-2xl text-emerald-700">+{FormatNumber({ value: dayDetails.inc })}</p>
                                    </div>
                                    <div className="bg-rose-50 p-4 rounded-2xl border border-rose-200 text-center">
                                        <p className="text-sm text-rose-600 mb-1">รายจ่าย</p>
                                        <p className="font-bold text-xl sm:text-2xl text-rose-700">-{FormatNumber({ value: dayDetails.exp })}</p>
                                    </div>
                                    <div className={`p-4 rounded-2xl border text-center ${dayDetails.net >= 0 ? 'bg-indigo-50 border-indigo-200 text-indigo-700' : 'bg-orange-50 border-orange-200 text-orange-700'}`}>
                                        <p className="text-sm mb-1 opacity-80">ยอดสุทธิ</p>
                                        <p className="font-bold text-xl sm:text-2xl">{dayDetails.net > 0 ? '+' : ''}{FormatNumber({ value: dayDetails.net })}</p>
                                    </div>
                                </div>

                                {/* Attendance Summary */}
                                <div>
                                    <h4 className="font-bold text-lg text-slate-700 mb-4 flex items-center gap-2">
                                        <span className="w-2 h-6 bg-blue-500 rounded-full"></span>
                                        การมาทำงาน
                                    </h4>
                                    <div className="grid grid-cols-2 gap-4">
                                        <div className="flex items-center gap-4 bg-white p-4 rounded-2xl border border-slate-200 shadow-sm">
                                            <div className="w-12 h-12 rounded-full bg-blue-100 text-blue-600 flex items-center justify-center text-xl font-bold">
                                                {dayDetails.presentCount}
                                            </div>
                                            <div>
                                                <p className="font-bold text-slate-800">มาทำงาน</p>
                                                <p className="text-sm text-slate-500">พนักงานเข้ากะ</p>
                                            </div>
                                        </div>
                                        <div className="flex items-center gap-4 bg-white p-4 rounded-2xl border border-slate-200 shadow-sm">
                                            <div className="w-12 h-12 rounded-full bg-amber-100 text-amber-600 flex items-center justify-center text-xl font-bold">
                                                {dayDetails.leaveCount}
                                            </div>
                                            <div>
                                                <p className="font-bold text-slate-800">ลางาน</p>
                                                <p className="text-sm text-slate-500">{dayDetails.leaveNames.join(', ') || '-'}</p>
                                            </div>
                                        </div>
                                    </div>
                                </div>

                                {/* Daily Logs Gallery */}
                                <div>
                                    <h4 className="font-bold text-lg text-slate-700 mb-4 flex items-center gap-2">
                                        <span className="w-2 h-6 bg-purple-500 rounded-full"></span>
                                        บันทึกกิจกรรมประจำวันแทรกเตอร์ / ทราย
                                    </h4>

                                    <div className="space-y-3">
                                        {/* Machine / เที่ยวรถ */}
                                        {(dayDetails.machineLogs || []).map(t => (
                                            <div key={t.id} className="flex gap-4 p-4 border border-slate-200 rounded-2xl bg-white shadow-sm hover:shadow-md transition-shadow">
                                                <div className="w-12 h-12 rounded-2xl bg-orange-100 flex items-center justify-center text-2xl shrink-0">🚜</div>
                                                <div className="flex-1">
                                                    {t.subCategory === 'VehicleTrip' ? (
                                                        <>
                                                            <div className="font-bold text-slate-800">{t.description || 'เที่ยวรถ'}</div>
                                                            {t.workDetails && <div className="text-slate-600 mt-1">{t.workDetails}</div>}
                                                            {t.amount > 0 && <div className="text-amber-600 font-medium mt-1">฿{t.amount.toLocaleString()}</div>}
                                                        </>
                                                    ) : (
                                                        <>
                                                            <div className="font-bold text-lg text-slate-800">
                                                                {t.machineId || 'เครื่องจักร'} <span className="text-orange-500 font-medium">({t.machineHours ?? 0} ชม.)</span>
                                                            </div>
                                                            <div className="text-slate-600 mt-1">{t.note || t.description}</div>
                                                            {t.location && <div className="text-sm text-slate-400 mt-2 flex items-center gap-1">📍 {t.location}</div>}
                                                        </>
                                                    )}
                                                </div>
                                            </div>
                                        ))}

                                        {/* Sand Logs — จาก DailyLog subCategory Sand */}
                                        {(dayDetails.sandLogs || []).map(t => (
                                            <div key={t.id} className="flex gap-4 p-4 border border-slate-200 rounded-2xl bg-white shadow-sm hover:shadow-md transition-shadow">
                                                <div className="w-12 h-12 rounded-2xl bg-cyan-100 flex items-center justify-center text-2xl shrink-0">🌊</div>
                                                <div className="flex-1">
                                                    <div className="flex justify-between items-start">
                                                        <div className="font-bold text-lg text-slate-800">
                                                            ล้างทราย <span className="text-cyan-600 font-medium">{(t.sandMorning || 0) + (t.sandAfternoon || 0)} คิว</span>
                                                        </div>
                                                        <span className="text-xs font-bold px-2 py-1 rounded bg-slate-100 text-slate-600">
                                                            {t.sandMachineType === 'Old' ? 'เครื่องเก่า' : t.sandMachineType === 'New' ? 'เครื่องใหม่' : '-'}
                                                        </span>
                                                    </div>
                                                    <div className="text-slate-600 mt-1">เช้า: {t.sandMorning ?? 0} คิว / บ่าย: {t.sandAfternoon ?? 0} คิว</div>
                                                    {t.sandTransport != null && t.sandTransport > 0 && <div className="text-slate-500 text-sm mt-1">🚛 ขน: {t.sandTransport} คิว</div>}
                                                    {t.amount > 0 && <div className="text-slate-500 text-sm mt-1">฿{t.amount.toLocaleString()}</div>}
                                                </div>
                                            </div>
                                        ))}

                                        {/* Event Logs */}
                                        {(dayDetails.eventLogs || []).map(t => (
                                            <div key={t.id} className="flex gap-4 p-4 border border-orange-100 rounded-2xl bg-amber-50/50 shadow-sm">
                                                <div className="w-12 h-12 rounded-2xl bg-amber-100 flex items-center justify-center text-2xl shrink-0">📌</div>
                                                <div className="font-medium text-slate-800">{t.description}</div>
                                            </div>
                                        ))}

                                        {/* Empty State */}
                                        {!(dayDetails.machineLogs?.length) && !(dayDetails.sandLogs?.length) && !(dayDetails.eventLogs?.length) && (
                                            <div className="text-center bg-slate-50 border border-dashed border-slate-200 rounded-2xl p-8 text-slate-400">
                                                ไม่มีบันทึกกิจกรรมพิเศษสำหรับวันนี้
                                            </div>
                                        )}
                                    </div>
                                </div>

                                {/* Transactions Grid */}
                                <div>
                                    <h4 className="font-bold text-lg text-slate-700 mb-4 flex items-center gap-2">
                                        <span className="w-2 h-6 bg-emerald-500 rounded-full"></span>
                                        รายการเดินบัญชีทั้งหมด
                                    </h4>

                                    <div className="space-y-3">
                                        {(dayDetails.transactions || []).map(t => (
                                            <div key={t.id} className="group p-4 bg-white border border-slate-200 rounded-2xl shadow-sm hover:shadow-md transition-all flex justify-between items-center">
                                                <div className="flex items-center gap-4">
                                                    <div className={`w-10 h-10 rounded-full flex items-center justify-center font-bold ${t.type === 'Income' ? 'bg-emerald-100 text-emerald-600' :
                                                        'bg-rose-100 text-rose-600'
                                                        }`}>
                                                        {t.type === 'Income' ? '+' : '-'}
                                                    </div>
                                                    <div>
                                                        <p className="font-bold text-slate-800 line-clamp-1">{t.description}</p>
                                                        <p className="text-sm text-slate-500">{t.category} {t.subCategory ? `• ${t.subCategory}` : ''}</p>
                                                    </div>
                                                </div>
                                                <div className={`font-bold text-lg ${t.type === 'Income' ? 'text-emerald-600' :
                                                    t.category === 'Leave' ? 'text-amber-500' : 'text-rose-500'
                                                    }`}>
                                                    {t.amount > 0 ? `฿${FormatNumber({ value: t.amount })}` : (t.category === 'Leave' ? 'ลา' : '-')}
                                                </div>
                                            </div>
                                        ))}

                                        {dayDetails.transactions?.length === 0 && (
                                            <div className="text-center p-6 text-slate-400 italic">ไม่มีรายการเดินบัญชี</div>
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
