import { useMemo, useState } from 'react';
import { Calendar, RefreshCw, LayoutGrid, Truck, Droplets } from 'lucide-react';
import type { AppSettings, Employee, Transaction } from '../../types';
import { formatDateBE } from '../../utils';
import { MOBILE_DAILY_MODULES, dailyHeaderCountedModules, type DailyModuleDef } from './mobileDailyModules';
import {
    dailyLeaveModuleStatusLabel,
    dailySandWashModuleStatusLabel,
    filterTransactionsForDay,
    resolveDailyModuleFillStatus,
} from './dailyModuleTransactions';
import RecordModuleCard from './RecordModuleCard';
import CalendarView from '../Dashboard/CalendarView';

const formatBuddhistDateButton = (ymd: string): string => {
    const weekdays = ['วันอาทิตย์', 'วันจันทร์', 'วันอังคาร', 'วันพุธ', 'วันพฤหัสบดี', 'วันศุกร์', 'วันเสาร์'];
    const months = [
        'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
        'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
    ];
    const p = ymd.split('-').map(Number);
    if (p.length !== 3 || p.some(n => Number.isNaN(n))) return ymd;
    const d = new Date(p[0], p[1] - 1, p[2]);
    const be = d.getFullYear() + 543;
    return `${weekdays[d.getDay()]} ที่ ${d.getDate()} เดือน${months[d.getMonth()]} พ.ศ.${be}`;
};

type MobileAndroidHomeProps = {
    settings: AppSettings;
    appIcon: string;
    selectedDate: string;
    transactions: Transaction[];
    employees: Employee[];
    serverOnline?: boolean;
    onPickDay: () => void;
    onSelectDay: (ymd: string) => void;
    onRefresh: () => void;
    onOpenModule: (mod: DailyModuleDef) => void;
    onSaveTransaction: (t: Transaction) => void | Promise<void>;
    onDeleteTransaction?: (id: string) => void | Promise<void>;
};

const MobileAndroidHome = ({
    settings,
    appIcon,
    selectedDate,
    transactions,
    employees,
    serverOnline = true,
    onPickDay,
    onSelectDay,
    onRefresh,
    onOpenModule,
    onSaveTransaction,
    onDeleteTransaction,
}: MobileAndroidHomeProps) => {
    const [countMenuOpen, setCountMenuOpen] = useState(false);
    const dayTransactions = useMemo(
        () => filterTransactionsForDay(selectedDate, transactions),
        [selectedDate, transactions],
    );

    const menuStatusByCategory = useMemo(() => {
        const map: Record<string, ReturnType<typeof resolveDailyModuleFillStatus>> = {};
        for (const m of MOBILE_DAILY_MODULES) {
            map[m.category] = resolveDailyModuleFillStatus(selectedDate, m.category, transactions);
        }
        return map;
    }, [selectedDate, transactions]);

    const modulesForHeader = useMemo(
        () => dailyHeaderCountedModules(dayTransactions),
        [dayTransactions],
    );

    const doneCount = modulesForHeader.filter(m => menuStatusByCategory[m.category] === 'complete').length;
    const incompleteCount = modulesForHeader.filter(m => menuStatusByCategory[m.category] === 'incomplete').length;
    const headerTotal = modulesForHeader.length;

    const lastLabel =
        dayTransactions.length > 0
            ? formatDateBE(String(dayTransactions[0].date || '').slice(0, 10))
            : '—';

    const tripModule = useMemo(
        () => MOBILE_DAILY_MODULES.find(m => m.category === 'จำนวนเที่ยวรถ') ?? null,
        [],
    );
    const sandSieveModule = useMemo(
        () => MOBILE_DAILY_MODULES.find(m => m.category === 'บันทึกการร่อนทราย') ?? null,
        [],
    );

    return (
        <div className="flex min-h-0 flex-1 flex-col bg-[#F8FAFC] p-3 pb-4">
            <div
                className="shrink-0 rounded-3xl border border-[#E7ECF3] bg-white px-3.5 py-3 shadow-[0_3px_10px_rgba(0,0,0,0.07)]"
            >
                <div className="flex items-start gap-2.5">
                    <div className="flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden rounded-xl bg-[#11A8BA] text-lg font-black text-white">
                        {appIcon.startsWith('http') || appIcon.startsWith('/') || appIcon.startsWith('data:') ? (
                            <img src={appIcon} alt="" className="h-full w-full object-contain" />
                        ) : (
                            <span>{appIcon.slice(0, 1)}</span>
                        )}
                    </div>
                    <div className="min-w-0 flex-1">
                        <h1 className="text-lg font-bold leading-tight text-[#1A2433]">บันทึกประจำวัน</h1>
                        <p className="truncate text-sm text-[#6B7788]">{settings.appName}</p>
                    </div>
                    <button
                        type="button"
                        onClick={onRefresh}
                        className="shrink-0 rounded-lg p-1.5 text-[#3A4A5E] touch-manipulation active:scale-95"
                        aria-label="รีเฟรช"
                    >
                        <RefreshCw size={22} />
                    </button>
                </div>
                <button
                    type="button"
                    onClick={onPickDay}
                    className="mt-2.5 flex w-full items-center justify-end gap-1 rounded-[20px] border border-[#D9E1EC] bg-[#F5F8FC] px-3 py-2 touch-manipulation active:scale-[0.99]"
                >
                    <Calendar size={14} className="shrink-0 text-[#00A8C4]" />
                    <span className="truncate text-left text-base font-extrabold text-[#00A8C4]">
                        {formatBuddhistDateButton(selectedDate)}
                    </span>
                </button>
                <div className="mt-2 flex flex-wrap items-center gap-2 text-xs font-medium text-[#6B7788]">
                    <span className={serverOnline ? 'text-emerald-600' : 'text-amber-600'}>
                        {serverOnline ? 'ออนไลน์' : 'ออฟไลน์'}
                    </span>
                    <span>·</span>
                    <span>อัปเดตล่าสุด {lastLabel}</span>
                </div>
                {headerTotal > 0 && (
                    <p className="mt-2 text-sm font-semibold text-[#1A2433]">
                        บันทึกครบ {doneCount}/{headerTotal} เมนู
                        {incompleteCount > 0 ? (
                            <span className="ml-1 font-medium text-amber-600">· ยังไม่ครบ {incompleteCount}</span>
                        ) : null}
                    </p>
                )}
            </div>

            <div className="mt-3 shrink-0 rounded-3xl border border-[#E7ECF3] bg-white p-2 shadow-[0_3px_10px_rgba(0,0,0,0.07)]">
                <CalendarView
                    transactions={transactions}
                    employees={employees}
                    onSaveTransaction={onSaveTransaction}
                    onDeleteTransaction={onDeleteTransaction}
                    onDaySelected={onSelectDay}
                />
            </div>

            <div className="mt-3 min-h-0 flex-1 overflow-y-auto overscroll-y-contain rounded-[28px] border border-[#E7ECF3] bg-white p-2 shadow-[0_3px_10px_rgba(0,0,0,0.07)]">
                {!countMenuOpen ? (
                    <div className="grid grid-cols-3 gap-2.5 sm:grid-cols-3 md:grid-cols-4">
                        <div className="home-menu-tile-in flex justify-center" style={{ animationDelay: '0ms' }}>
                            <button
                                type="button"
                                onClick={() => setCountMenuOpen(true)}
                                className="flex h-full w-full min-h-[112px] flex-col items-start justify-between rounded-2xl border border-[#D8E6F7] bg-[#F4F8FE] p-3 text-left shadow-sm transition-transform touch-manipulation active:scale-[0.98]"
                            >
                                <LayoutGrid size={22} className="text-[#1565C0]" />
                                <div>
                                    <p className="text-sm font-extrabold leading-snug text-[#1D2A3A]">บันทึกและนับจำนวน</p>
                                    <p className="mt-0.5 text-[11px] font-semibold text-[#6B7788]">จำนวนเที่ยวรถ / การร่อนทราย</p>
                                </div>
                            </button>
                        </div>
                        {MOBILE_DAILY_MODULES.map((m, index) => {
                            const fill = menuStatusByCategory[m.category] ?? 'pending';
                            return (
                                <div
                                    key={m.category}
                                    className="home-menu-tile-in flex justify-center"
                                    style={{ animationDelay: `${Math.min((index + 1) * 40, 400)}ms` }}
                                >
                                    <RecordModuleCard
                                        title={m.title}
                                        icon={m.icon}
                                        tileColor={m.color}
                                        fillStatus={fill}
                                        completeStatusLabelOverride={
                                            m.category === 'ลางาน'
                                                ? dailyLeaveModuleStatusLabel(selectedDate, transactions, employees)
                                                : m.category === 'บันทึกการร่อนทราย'
                                                  ? dailySandWashModuleStatusLabel(selectedDate, transactions)
                                                  : undefined
                                        }
                                        statusMaxLines={
                                            m.category === 'ลางาน' || m.category === 'บันทึกการร่อนทราย'
                                                ? 3
                                                : 2
                                        }
                                        onTap={() => onOpenModule(m)}
                                    />
                                </div>
                            );
                        })}
                    </div>
                ) : (
                    <div className="flex h-full min-h-[min(72vh,640px)] flex-col p-2 sm:p-3">
                        <div className="mb-3 flex items-center justify-between">
                            <h2 className="text-base font-extrabold text-[#1A2433]">บันทึกและนับจำนวน</h2>
                            <button
                                type="button"
                                onClick={() => setCountMenuOpen(false)}
                                className="rounded-xl border border-[#D9E1EC] bg-white px-3 py-1.5 text-xs font-bold text-[#4A5A70] touch-manipulation active:scale-95"
                            >
                                กลับเมนูหลัก
                            </button>
                        </div>
                        <div className="grid min-h-0 flex-1 grid-cols-2 gap-3">
                            <button
                                type="button"
                                onClick={() => tripModule && onOpenModule(tripModule)}
                                className="flex h-full min-h-[min(46vh,360px)] flex-col items-start justify-between rounded-3xl border border-[#D2E7FF] bg-[#F2F8FF] p-5 text-left shadow-sm transition-transform touch-manipulation active:scale-[0.99]"
                            >
                                <Truck size={32} className="text-[#1D8FE1]" />
                                <div>
                                    <p className="text-xl font-extrabold text-[#1A2433]">จำนวนเที่ยวรถ</p>
                                    <p className="mt-1 text-sm font-semibold text-[#5C7088]">บันทึกเที่ยวรถดรัมและสรุปเที่ยว</p>
                                </div>
                            </button>
                            <button
                                type="button"
                                onClick={() => sandSieveModule && onOpenModule(sandSieveModule)}
                                className="flex h-full min-h-[min(46vh,360px)] flex-col items-start justify-between rounded-3xl border border-[#FFD6EB] bg-[#FFF2FA] p-5 text-left shadow-sm transition-transform touch-manipulation active:scale-[0.99]"
                            >
                                <Droplets size={32} className="text-[#E91E8F]" />
                                <div>
                                    <p className="text-xl font-extrabold text-[#1A2433]">การร่อนทราย</p>
                                    <p className="mt-1 text-sm font-semibold text-[#5C7088]">บันทึกผลร่อนทรายและจำนวนคิว</p>
                                </div>
                            </button>
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
};

export default MobileAndroidHome;
