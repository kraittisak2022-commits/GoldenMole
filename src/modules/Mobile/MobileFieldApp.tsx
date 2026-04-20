import { useState, useMemo, useCallback } from 'react';
import {
    Home,
    ClipboardList,
    Users,
    List,
    MoreHorizontal,
    Sun,
    Moon,
    LogOut,
    Monitor,
    User,
    ChevronLeft,
    Settings,
    Shield,
    Calendar,
    ChevronRight,
    Wallet,
} from 'lucide-react';
import {
    AppSettings,
    Employee,
    Transaction,
    AdminUser,
    AdminUiTheme,
    AdminLog,
} from '../../types';
import { getToday, normalizeDate, formatDateBE } from '../../utils';
import DailyStepRecorder from '../Dashboard/DailyStepRecorder';
import LaborModule from '../Labor/LaborModule';
import RecordManager from '../DataList/RecordManager';
import SettingsModule from '../Settings/SettingsModule';
import AdminModule from '../Admin/AdminModule';
import FormatNumber from '../../components/ui/FormatNumber';

type MobileTab = 'home' | 'daily' | 'labor' | 'records' | 'more';

interface MobileFieldAppProps {
    settings: AppSettings;
    employees: Employee[];
    transactions: Transaction[];
    admins: AdminUser[];
    adminLogs: AdminLog[];
    currentAdmin: AdminUser;
    appVersion: string;
    latestVersionNote: string;
    autoVersionNotes: string[];
    appIcon: string;
    darkMode: boolean;
    onToggleDarkMode: () => void;
    onLogout: () => void;
    onSwitchToDesktop: () => void;
    onOpenAccount: () => void;
    onSaveTransaction: (t: Transaction) => void;
    onDeleteTransaction: (id: string) => void;
    handleSetTransactions: (updater: Transaction[] | ((prev: Transaction[]) => Transaction[])) => void;
    ensureEmployeeWage: (emp: Employee) => Promise<number>;
    handleSetSettings: (updater: AppSettings | ((prev: AppSettings) => AppSettings)) => void;
    handleSetAdmins: (updater: AdminUser[] | ((prev: AdminUser[]) => AdminUser[])) => void;
    onClearAllData: () => void | Promise<void>;
    onUpdateAdminProfile: (updates: {
        displayName?: string;
        avatar?: string;
        uiTheme?: AdminUiTheme;
        currentPassword?: string;
        newPassword?: string;
    }) => Promise<{ ok: boolean; message?: string }>;
    addLog: (action: string, details: string) => void;
}

const TAB_BAR: { id: MobileTab; label: string; icon: typeof Home }[] = [
    { id: 'home', label: 'สรุป', icon: Home },
    { id: 'daily', label: 'บันทึก', icon: ClipboardList },
    { id: 'labor', label: 'ค่าแรง', icon: Users },
    { id: 'records', label: 'รายการ', icon: List },
    { id: 'more', label: 'เมนู', icon: MoreHorizontal },
];

const CATEGORY_LABEL_TH: Record<string, string> = {
    Labor: 'ค่าแรง/ลา',
    Vehicle: 'การใช้รถ',
    Fuel: 'น้ำมัน',
    Maintenance: 'ซ่อมบำรุง',
    Income: 'รายรับ',
    Utilities: 'สาธารณูปโภค',
    Land: 'ที่ดิน',
    DailyLog: 'บันทึกงาน',
    Leave: 'ลา',
};

const POS_SLICE_COLORS_LIGHT = ['#1e3a8a', '#1d4ed8', '#2563eb', '#3b82f6', '#60a5fa', '#38bdf8'];
const POS_SLICE_COLORS_DARK = ['#3b82f6', '#60a5fa', '#93c5fd', '#38bdf8', '#7dd3fc', '#a5f3fc'];

function PosExpenseDonut({
    slices,
    centerMain,
    centerSub,
    darkMode,
}: {
    slices: { value: number; color: string; label: string }[];
    centerMain: string;
    centerSub: string;
    darkMode: boolean;
}) {
    const total = slices.reduce((a, s) => a + s.value, 0);
    const stroke = darkMode ? '#0f172a' : '#ffffff';
    const holeFill = darkMode ? '#1e293b' : '#ffffff';

    if (total <= 0) {
        return (
            <div className="relative mx-auto flex h-[220px] w-[220px] items-center justify-center">
                <div
                    className={`flex h-48 w-48 items-center justify-center rounded-full border-8 border-dashed ${
                        darkMode ? 'border-slate-600 text-slate-500' : 'border-slate-200 text-slate-400'
                    }`}
                >
                    <p className="px-6 text-center text-sm font-medium">ยังไม่มีรายจ่ายในวันนี้</p>
                </div>
            </div>
        );
    }

    let cumulative = 0;
    const getCoords = (pct: number) => [Math.cos(2 * Math.PI * pct), Math.sin(2 * Math.PI * pct)] as const;

    return (
        <div className="relative mx-auto h-[220px] w-[220px]">
            <svg viewBox="-1 -1 2 2" className="h-full w-full -rotate-90 drop-shadow-sm">
                {slices.map((slice, i) => {
                    const pct = slice.value / total;
                    const start = getCoords(cumulative);
                    cumulative += pct;
                    const end = getCoords(cumulative);
                    const largeArc = pct > 0.5 ? 1 : 0;
                    const d = [`M ${start[0]} ${start[1]}`, `A 1 1 0 ${largeArc} 1 ${end[0]} ${end[1]}`, 'L 0 0'].join(' ');
                    return <path key={i} d={d} fill={slice.color} stroke={stroke} strokeWidth="0.04" />;
                })}
                <circle cx="0" cy="0" r="0.58" fill={holeFill} />
            </svg>
            <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center pt-1">
                <span className={`text-xs font-semibold ${darkMode ? 'text-slate-400' : 'text-slate-500'}`}>{centerSub}</span>
                <span className={`mt-0.5 text-2xl font-black tabular-nums tracking-tight ${darkMode ? 'text-white' : 'text-slate-900'}`}>
                    {centerMain}
                </span>
            </div>
        </div>
    );
}

const MobileFieldApp = (props: MobileFieldAppProps) => {
    const {
        settings,
        employees,
        transactions,
        admins,
        adminLogs,
        currentAdmin,
        appVersion,
        latestVersionNote,
        autoVersionNotes,
        appIcon,
        darkMode,
        onToggleDarkMode,
        onLogout,
        onSwitchToDesktop,
        onOpenAccount,
        onSaveTransaction,
        onDeleteTransaction,
        handleSetTransactions,
        ensureEmployeeWage,
        handleSetSettings,
        handleSetAdmins,
        onClearAllData,
        onUpdateAdminProfile,
        addLog,
    } = props;

    const [tab, setTab] = useState<MobileTab>('home');
    const [morePanel, setMorePanel] = useState<'root' | 'settings' | 'admin'>('root');
    const [summaryDate, setSummaryDate] = useState(() => getToday());
    const [recordCatFilter, setRecordCatFilter] = useState<string | null>(null);

    const dayTransactions = useMemo(
        () => transactions.filter(t => normalizeDate(t.date) === summaryDate),
        [transactions, summaryDate]
    );

    const posStats = useMemo(() => {
        const income = dayTransactions.filter(t => t.type === 'Income').reduce((a, t) => a + (t.amount || 0), 0);
        const expense = dayTransactions.filter(t => t.type === 'Expense').reduce((a, t) => a + (t.amount || 0), 0);
        const byCat = new Map<string, number>();
        for (const t of dayTransactions) {
            if (t.type !== 'Expense') continue;
            const c = t.category || 'อื่นๆ';
            byCat.set(c, (byCat.get(c) || 0) + (t.amount || 0));
        }
        const sorted = Array.from(byCat.entries()).sort((a, b) => b[1] - a[1]);
        const colors = darkMode ? POS_SLICE_COLORS_DARK : POS_SLICE_COLORS_LIGHT;
        const top = sorted.slice(0, 5);
        const restSum = sorted.slice(5).reduce((a, [, v]) => a + v, 0);
        const sliceList: { value: number; color: string; label: string }[] = top.map(([label, value], i) => ({
            value,
            color: colors[i % colors.length],
            label: CATEGORY_LABEL_TH[label] || label,
        }));
        if (restSum > 0) {
            sliceList.push({
                value: restSum,
                color: colors[sliceList.length % colors.length],
                label: 'อื่นๆ',
            });
        }
        const laborHeadcount = dayTransactions
            .filter(t => t.category === 'Labor' && t.laborStatus === 'Work')
            .reduce((acc, t) => acc + (t.employeeIds?.length || 0), 0);
        return {
            count: dayTransactions.length,
            income,
            expense,
            sliceList,
            expenseTotal: expense,
            laborHeadcount,
        };
    }, [dayTransactions, darkMode]);

    const filteredTransactionsForRecords = useMemo(() => {
        if (!recordCatFilter) return transactions;
        return transactions.filter(t => t.category === recordCatFilter);
    }, [transactions, recordCatFilter]);

    const recordFilterChips = useMemo(() => {
        const set = new Set<string>();
        transactions.forEach(t => {
            if (t.category) set.add(t.category);
        });
        return ['', ...Array.from(set).sort()];
    }, [transactions]);

    const title =
        tab === 'home'
            ? 'สรุปวันนี้'
            : tab === 'daily'
              ? 'บันทึกประจำวัน'
              : tab === 'labor'
                ? 'ค่าแรง / ลา'
                : tab === 'records'
                  ? 'รายการบันทึก'
                  : morePanel === 'settings'
                    ? 'ตั้งค่า'
                    : morePanel === 'admin'
                      ? 'จัดการแอดมิน'
                      : 'เมนู';

    const showBack =
        (tab === 'more' && morePanel !== 'root') || tab === 'daily' || tab === 'labor' || tab === 'records';

    const onHeaderBack = useCallback(() => {
        if (tab === 'more' && morePanel !== 'root') {
            setMorePanel('root');
            return;
        }
        setTab('home');
    }, [tab, morePanel]);

    const shellBg = darkMode
        ? 'bg-slate-950 text-slate-100'
        : 'bg-gradient-to-b from-[#eef3fb] via-[#e8edf5] to-[#dfe8f4] text-slate-900';
    const cardBg = darkMode ? 'bg-slate-900/90 ring-1 ring-white/10' : 'bg-white shadow-lg shadow-slate-900/5 ring-1 ring-slate-200/80';
    const headerBg = darkMode ? 'border-slate-800 bg-slate-900/95' : 'border-slate-200/80 bg-white/95';
    const tabBarBg = darkMode ? 'border-slate-800 bg-slate-900/98' : 'border-slate-200 bg-white/98';

    const mainBottomPad =
        tab === 'home'
            ? 'pb-[calc(7.5rem+env(safe-area-inset-bottom,0px))]'
            : 'pb-[calc(4.75rem+env(safe-area-inset-bottom,0px))]';

    const homeSlicePreview = posStats.sliceList.slice(0, 4);
    const homeSliceMore = posStats.sliceList.length - homeSlicePreview.length;

    return (
        <div className={`relative h-[100dvh] max-h-[100dvh] w-full overflow-hidden font-sans touch-manipulation ${shellBg}`} style={{ overscrollBehaviorY: 'none' }}>
            {!darkMode && (
                <div
                    className="pointer-events-none absolute inset-x-0 top-0 h-52 w-full opacity-90"
                    style={{
                        background: 'radial-gradient(ellipse 90% 80% at 50% -25%, rgba(59,130,246,0.2), transparent 72%)',
                    }}
                />
            )}
            <div className="relative mx-auto flex h-full w-full max-w-full min-w-0 flex-col sm:max-w-lg">
                <header
                    className={`sticky top-0 z-20 flex items-center gap-2 border-b px-3 py-2.5 backdrop-blur-md ${headerBg}`}
                    style={{ paddingTop: 'max(0.5rem, env(safe-area-inset-top))' }}
                >
                    {showBack ? (
                        <button
                            type="button"
                            onClick={onHeaderBack}
                            className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl touch-manipulation active:scale-95 ${
                                darkMode ? 'bg-slate-800 text-white hover:bg-slate-700' : 'bg-slate-100 text-slate-800 hover:bg-slate-200'
                            }`}
                            aria-label="กลับ"
                        >
                            <ChevronLeft size={22} strokeWidth={2.5} />
                        </button>
                    ) : (
                        <div
                            className={`flex h-11 w-11 shrink-0 items-center justify-center overflow-hidden rounded-2xl shadow-inner ${
                                darkMode ? 'bg-blue-600' : 'bg-blue-600'
                            }`}
                        >
                            {appIcon.startsWith('http') || appIcon.startsWith('data:') ? (
                                <img src={appIcon} alt="" className="h-full w-full object-cover" />
                            ) : (
                                <span className="text-lg font-black text-white">{appIcon}</span>
                            )}
                        </div>
                    )}
                    <div className="min-w-0 flex-1">
                        <h1 className="truncate text-lg font-black leading-tight tracking-tight text-slate-900 dark:text-white">{title}</h1>
                        {tab !== 'home' && (
                            <p className="truncate text-[10px] font-medium text-slate-500 dark:text-slate-400">{settings.appName}</p>
                        )}
                    </div>
                    <button
                        type="button"
                        onClick={onToggleDarkMode}
                        className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl touch-manipulation active:scale-95 ${
                            darkMode ? 'bg-slate-800 text-amber-300' : 'bg-slate-100 text-slate-700'
                        }`}
                        aria-label="ธีม"
                    >
                        {darkMode ? <Sun size={20} /> : <Moon size={20} />}
                    </button>
                </header>

                <main
                    className={`mobile-field-app min-h-0 flex-1 overflow-y-auto overscroll-y-contain px-3 pt-3 ${mainBottomPad}`}
                    style={{ WebkitTapHighlightColor: 'transparent', overscrollBehaviorY: 'contain' }}
                >
                    {tab === 'home' && (
                        <div className="animate-fade-in space-y-3">
                            <div className={`rounded-[1.75rem] p-4 shadow-xl shadow-slate-900/5 ring-1 backdrop-blur-sm ${cardBg}`}>
                                <div className="flex items-center justify-between gap-2">
                                    <label
                                        className={`flex min-h-[48px] flex-1 cursor-pointer items-center justify-center gap-2 rounded-2xl border px-4 text-base font-bold touch-manipulation ${
                                            darkMode ? 'border-slate-600 bg-slate-800 text-white' : 'border-slate-200/80 bg-white/80 text-slate-800'
                                        }`}
                                    >
                                        <Calendar className={`h-5 w-5 shrink-0 ${darkMode ? 'text-blue-300' : 'text-blue-600'}`} />
                                        <input
                                            type="date"
                                            value={summaryDate}
                                            onChange={e => setSummaryDate(e.target.value)}
                                            className="sr-only"
                                        />
                                        <span>{formatDateBE(summaryDate)}</span>
                                    </label>
                                </div>

                                <div className="mt-4 text-center">
                                    <p className={`font-mono text-4xl font-black tabular-nums leading-none tracking-tight ${darkMode ? 'text-white' : 'text-slate-900'}`}>
                                        <FormatNumber value={posStats.expense} />
                                    </p>
                                    <p className={`mt-2 text-sm font-bold ${darkMode ? 'text-slate-400' : 'text-slate-500'}`}>รายจ่ายวันนี้</p>
                                    <div
                                        className={`mx-auto mt-3 flex max-w-xs items-center justify-center gap-2 rounded-2xl py-2.5 text-sm font-bold ${
                                            darkMode ? 'bg-emerald-500/15 text-emerald-300' : 'bg-emerald-50 text-emerald-800'
                                        }`}
                                    >
                                        <Wallet size={17} className="shrink-0" />
                                        <FormatNumber value={posStats.income} />
                                        <span className="font-semibold opacity-80">รับ</span>
                                    </div>
                                </div>

                                <div className="mt-5">
                                    <PosExpenseDonut
                                        slices={posStats.sliceList}
                                        centerMain={`${posStats.count}`}
                                        centerSub="รายการ"
                                        darkMode={darkMode}
                                    />
                                </div>

                                <div className="mt-2 space-y-2">
                                    {homeSlicePreview.length === 0 ? (
                                        <p className={`py-3 text-center text-sm ${darkMode ? 'text-slate-500' : 'text-slate-500'}`}>ไม่มีรายจ่ายวันนี้</p>
                                    ) : (
                                        homeSlicePreview.map(row => {
                                            const pct = posStats.expenseTotal > 0 ? (row.value / posStats.expenseTotal) * 100 : 0;
                                            return (
                                                <button
                                                    key={row.label}
                                                    type="button"
                                                    onClick={() => {
                                                        setRecordCatFilter(null);
                                                        setTab('records');
                                                    }}
                                                    className={`flex min-h-[52px] w-full items-center gap-3 rounded-2xl border px-3 active:scale-[0.99] touch-manipulation ${
                                                        darkMode ? 'border-slate-700/80 bg-slate-800/40' : 'border-slate-100 bg-white/70'
                                                    }`}
                                                >
                                                    <span className="h-9 w-1 shrink-0 rounded-full" style={{ backgroundColor: row.color }} />
                                                    <div className="min-w-0 flex-1 text-left">
                                                        <p className="truncate text-[15px] font-bold">{row.label}</p>
                                                        <p className={`text-xs font-medium ${darkMode ? 'text-slate-500' : 'text-slate-500'}`}>{pct.toFixed(0)}%</p>
                                                    </div>
                                                    <span className="shrink-0 font-mono text-[15px] font-black tabular-nums">
                                                        <FormatNumber value={row.value} />
                                                    </span>
                                                    <ChevronRight className={`h-5 w-5 shrink-0 opacity-40`} />
                                                </button>
                                            );
                                        })
                                    )}
                                    {homeSliceMore > 0 && (
                                        <button
                                            type="button"
                                            onClick={() => {
                                                setRecordCatFilter(null);
                                                setTab('records');
                                            }}
                                            className={`w-full rounded-2xl py-3 text-sm font-bold touch-manipulation ${darkMode ? 'text-blue-300' : 'text-blue-700'}`}
                                        >
                                            + อีก {homeSliceMore} หมวด · ดูรายการ
                                        </button>
                                    )}
                                </div>
                            </div>
                        </div>
                    )}

                    {tab === 'daily' && (
                        <DailyStepRecorder
                            mobileShell
                            employees={employees}
                            settings={settings}
                            transactions={transactions}
                            onSaveTransaction={onSaveTransaction}
                            onDeleteTransaction={onDeleteTransaction}
                            ensureEmployeeWage={ensureEmployeeWage}
                        />
                    )}

                    {tab === 'labor' && (
                        <div className={`rounded-[1.75rem] p-3 pb-4 shadow-md ring-1 ${cardBg}`}>
                            <LaborModule
                                employees={employees}
                                settings={settings}
                                onSaveTransaction={onSaveTransaction}
                                onDeleteTransaction={onDeleteTransaction}
                                transactions={transactions}
                                setTransactions={handleSetTransactions}
                                ensureEmployeeWage={ensureEmployeeWage}
                            />
                        </div>
                    )}

                    {tab === 'records' && (
                        <div className="space-y-2">
                            <div className="flex gap-1.5 overflow-x-auto pb-1 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
                                {recordFilterChips.map(key => {
                                    const active = (key || null) === (recordCatFilter || '');
                                    const label = !key ? 'ทั้งหมด' : CATEGORY_LABEL_TH[key] || key;
                                    return (
                                        <button
                                            key={key || 'all'}
                                            type="button"
                                            onClick={() => setRecordCatFilter(key || null)}
                                            className={`min-h-[40px] shrink-0 rounded-full border px-3.5 text-xs font-bold touch-manipulation ${
                                                active
                                                    ? 'border-blue-600 bg-blue-600 text-white dark:border-blue-500 dark:bg-blue-500'
                                                    : darkMode
                                                      ? 'border-transparent bg-slate-800/80 text-slate-300'
                                                      : 'border-transparent bg-white/90 text-slate-600 shadow-sm'
                                            }`}
                                        >
                                            {label}
                                        </button>
                                    );
                                })}
                            </div>
                            <RecordManager
                                compact
                                darkMode={darkMode}
                                transactions={filteredTransactionsForRecords}
                                onDeleteTransaction={onDeleteTransaction}
                            />
                        </div>
                    )}

                    {tab === 'more' && morePanel === 'root' && (
                        <div className="space-y-3 pb-4">
                            {[
                                {
                                    key: 'account',
                                    icon: User,
                                    title: 'บัญชีแอดมิน',
                                    sub: currentAdmin.displayName,
                                    onClick: () => onOpenAccount(),
                                    tone: 'default' as const,
                                },
                                {
                                    key: 'settings',
                                    icon: Settings,
                                    title: 'ตั้งค่าระบบ',
                                    sub: 'รถ งาน ประเภทรายการ',
                                    onClick: () => setMorePanel('settings'),
                                    tone: 'default' as const,
                                },
                                ...(currentAdmin.role === 'SuperAdmin'
                                    ? [
                                          {
                                              key: 'admin',
                                              icon: Shield,
                                              title: 'จัดการแอดมิน',
                                              sub: 'สิทธิ์และบันทึก',
                                              onClick: () => setMorePanel('admin'),
                                              tone: 'default' as const,
                                          },
                                      ]
                                    : []),
                                {
                                    key: 'desktop',
                                    icon: Monitor,
                                    title: 'เว็บแอปปกติ',
                                    sub: 'โหมดเดสก์ท็อปเต็มรูปแบบ',
                                    onClick: onSwitchToDesktop,
                                    tone: 'blue' as const,
                                },
                            ].map(row => (
                                <button
                                    key={row.key}
                                    type="button"
                                    onClick={row.onClick}
                                    className={`flex w-full items-center gap-4 rounded-3xl border p-4 text-left touch-manipulation min-h-[60px] active:scale-[0.99] ${
                                        row.tone === 'blue'
                                            ? darkMode
                                                ? 'border-blue-500/40 bg-blue-500/15'
                                                : 'border-blue-200 bg-blue-50'
                                            : darkMode
                                              ? 'border-slate-700 bg-slate-900/80'
                                              : 'border-slate-200 bg-white shadow-sm'
                                    }`}
                                >
                                    <row.icon
                                        className={`h-6 w-6 shrink-0 ${row.tone === 'blue' ? 'text-blue-600 dark:text-blue-300' : 'text-blue-600 dark:text-blue-400'}`}
                                    />
                                    <div className="min-w-0 flex-1">
                                        <p className="font-black">{row.title}</p>
                                        <p className="truncate text-xs font-medium text-slate-500 dark:text-slate-400">{row.sub}</p>
                                    </div>
                                    <ChevronRight className="h-5 w-5 shrink-0 text-slate-400" />
                                </button>
                            ))}
                            <button
                                type="button"
                                onClick={onLogout}
                                className="flex w-full items-center justify-center gap-2 rounded-3xl border-2 border-red-400/50 bg-red-500/10 py-4 text-base font-black text-red-600 touch-manipulation active:scale-[0.99] dark:border-red-500/40 dark:bg-red-500/15 dark:text-red-300"
                            >
                                <LogOut size={20} />
                                ออกจากระบบ
                            </button>
                        </div>
                    )}

                    {tab === 'more' && morePanel === 'settings' && (
                        <div className={`rounded-3xl p-3 ${cardBg}`}>
                            <SettingsModule
                                settings={settings}
                                setSettings={handleSetSettings}
                                autoVersionNotes={autoVersionNotes}
                                onClearAllData={onClearAllData}
                                currentAdmin={currentAdmin}
                                onUpdateAdminProfile={onUpdateAdminProfile}
                            />
                        </div>
                    )}

                    {tab === 'more' && morePanel === 'admin' && currentAdmin.role === 'SuperAdmin' && (
                        <div className={`rounded-3xl p-3 ${cardBg}`}>
                            <AdminModule
                                admins={admins}
                                setAdmins={handleSetAdmins}
                                currentAdmin={currentAdmin}
                                logs={adminLogs}
                                addLog={addLog}
                            />
                        </div>
                    )}
                </main>

                {tab === 'home' && (
                    <div
                        className="pointer-events-none fixed inset-x-0 z-[38] mx-auto max-w-full px-3 sm:max-w-lg"
                        style={{ bottom: 'calc(3.65rem + env(safe-area-inset-bottom, 0px))' }}
                    >
                        <div className="pointer-events-auto flex items-center justify-between gap-3 rounded-2xl bg-blue-600 px-4 py-3 shadow-xl shadow-blue-900/25 dark:bg-blue-500">
                            <div className="min-w-0 text-white">
                                <p className="text-[10px] font-bold uppercase tracking-wide opacity-90">หน้างานวันนี้</p>
                                <p className="truncate font-mono text-lg font-black tabular-nums">
                                    {posStats.count} รายการ · <FormatNumber value={posStats.expense} />
                                </p>
                            </div>
                            <button
                                type="button"
                                onClick={() => setTab('daily')}
                                className="shrink-0 rounded-xl bg-white px-5 py-3 text-sm font-black text-blue-700 shadow-md touch-manipulation active:scale-95 dark:text-blue-800"
                            >
                                บันทึกประจำวัน
                            </button>
                        </div>
                    </div>
                )}

                <nav
                    className={`fixed bottom-0 left-0 right-0 z-40 mx-auto flex max-w-full justify-around border-t backdrop-blur-xl touch-manipulation sm:max-w-lg ${tabBarBg}`}
                    style={{ paddingBottom: 'max(0.35rem, env(safe-area-inset-bottom, 0px))' }}
                    aria-label="เมนูหลักมือถือ"
                >
                    {TAB_BAR.map(({ id, label, icon: Icon }) => {
                        const active = tab === id;
                        return (
                            <button
                                key={id}
                                type="button"
                                onClick={() => {
                                    setTab(id);
                                    if (id === 'more') setMorePanel('root');
                                }}
                                className={`flex min-h-[52px] min-w-0 flex-1 flex-col items-center justify-center gap-0.5 py-2 text-[10px] font-black ${
                                    active
                                        ? 'text-blue-600 dark:text-blue-400'
                                        : darkMode
                                          ? 'text-slate-500'
                                          : 'text-slate-500'
                                }`}
                            >
                                <span
                                    className={`flex h-10 w-10 items-center justify-center rounded-2xl transition-colors ${
                                        active
                                            ? darkMode
                                                ? 'bg-blue-500/20 text-blue-300'
                                                : 'bg-blue-100 text-blue-700'
                                            : darkMode
                                              ? 'text-slate-400'
                                              : 'text-slate-500'
                                    }`}
                                >
                                    <Icon size={22} strokeWidth={active ? 2.5 : 2} className="shrink-0" />
                                </span>
                                <span className="truncate px-0.5">{label}</span>
                            </button>
                        );
                    })}
                </nav>
            </div>
        </div>
    );
};

export default MobileFieldApp;
