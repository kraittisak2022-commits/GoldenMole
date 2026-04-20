import { useState, useMemo, useCallback } from 'react';
import {
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
    ChevronRight,
} from 'lucide-react';
import {
    AppSettings,
    Employee,
    Transaction,
    AdminUser,
    AdminUiTheme,
    AdminLog,
} from '../../types';
import DailyStepRecorder from '../Dashboard/DailyStepRecorder';
import LaborModule from '../Labor/LaborModule';
import RecordManager from '../DataList/RecordManager';
import SettingsModule from '../Settings/SettingsModule';
import AdminModule from '../Admin/AdminModule';

type MobileTab = 'home' | 'labor' | 'records' | 'more';

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

const TAB_BAR: { id: MobileTab; label: string; icon: typeof ClipboardList }[] = [
    { id: 'home', label: 'บันทึกงาน', icon: ClipboardList },
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
    const [recordCatFilter, setRecordCatFilter] = useState<string | null>(null);
    const [recordTypeFilter, setRecordTypeFilter] = useState<'Income' | 'Expense' | null>(null);

    const filteredTransactionsForRecords = useMemo(() => {
        let list = transactions;
        if (recordCatFilter) list = list.filter(t => t.category === recordCatFilter);
        if (recordTypeFilter === 'Income') list = list.filter(t => t.type === 'Income');
        if (recordTypeFilter === 'Expense') list = list.filter(t => t.type === 'Expense');
        return list;
    }, [transactions, recordCatFilter, recordTypeFilter]);

    const recordFilterChips = useMemo(() => {
        const set = new Set<string>();
        transactions.forEach(t => {
            if (t.category) set.add(t.category);
        });
        return ['', ...Array.from(set).sort()];
    }, [transactions]);

    const title =
        tab === 'home'
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

    const showBack = (tab === 'more' && morePanel !== 'root') || tab === 'labor' || tab === 'records';

    const onHeaderBack = useCallback(() => {
        if (tab === 'more' && morePanel !== 'root') {
            setMorePanel('root');
            return;
        }
        setTab('home');
    }, [tab, morePanel]);

    const shellBg = darkMode
        ? 'app-shell-dark'
        : 'bg-white text-slate-900';
    const cardBg = darkMode ? 'bg-slate-900/90 ring-1 ring-white/10' : 'bg-white shadow-lg shadow-slate-900/5 ring-1 ring-slate-200/80';
    const headerBg = darkMode ? 'border-slate-800 bg-slate-900/95' : 'border-slate-200/80 bg-white/95';
    const mainBottomPad = 'pb-[calc(5.75rem+env(safe-area-inset-bottom,0px))]';

    return (
        <div
            className={`mobile-shell-root relative flex min-h-0 w-full flex-col overflow-hidden font-sans touch-manipulation ${shellBg}`}
            style={{ overscrollBehaviorY: 'none', WebkitTouchCallout: 'none' }}
        >
            {!darkMode && (
                <div
                    className="pointer-events-none absolute inset-x-0 top-0 h-40 w-full opacity-60"
                    style={{
                        background: 'linear-gradient(to bottom, rgba(15,23,42,0.03), transparent)',
                    }}
                />
            )}
            <div className="relative mx-auto flex min-h-0 w-full max-w-full min-w-0 flex-1 flex-col sm:max-w-xl [@media(orientation:landscape)_and_(max-height:560px)]:max-w-full">
                <header
                    className={`sticky top-0 z-20 flex items-center gap-2 border-b py-2.5 ps-[max(0.75rem,env(safe-area-inset-left,0px))] pe-[max(0.75rem,env(safe-area-inset-right,0px))] backdrop-blur-md [@media(orientation:landscape)_and_(max-height:560px)]:gap-1.5 [@media(orientation:landscape)_and_(max-height:560px)]:py-2 ${headerBg}`}
                    style={{ paddingTop: 'max(0.5rem, env(safe-area-inset-top, 0px))' }}
                >
                    {showBack ? (
                        <button
                            type="button"
                            onClick={onHeaderBack}
                            className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl touch-manipulation active:scale-95 [@media(orientation:landscape)_and_(max-height:560px)]:h-10 [@media(orientation:landscape)_and_(max-height:560px)]:w-10 ${
                                darkMode ? 'bg-slate-800 text-white hover:bg-slate-700' : 'bg-slate-100 text-slate-800 hover:bg-slate-200'
                            }`}
                            aria-label="กลับ"
                        >
                            <ChevronLeft size={22} strokeWidth={2.5} />
                        </button>
                    ) : (
                        <div
                            className={`flex h-11 w-11 shrink-0 items-center justify-center overflow-hidden rounded-2xl shadow-inner [@media(orientation:landscape)_and_(max-height:560px)]:h-10 [@media(orientation:landscape)_and_(max-height:560px)]:w-10 ${
                                darkMode ? 'bg-blue-600' : 'bg-blue-600'
                            }`}
                        >
                            {appIcon.startsWith('http') || appIcon.startsWith('data:') ? (
                                <img src={appIcon} alt={settings.appName} className="h-full w-full object-cover" />
                            ) : (
                                <span className="text-lg font-black text-white">{appIcon}</span>
                            )}
                        </div>
                    )}
                    <div className="min-w-0 flex-1">
                        <h1 className="truncate text-lg font-black leading-tight tracking-tight text-slate-900 [@media(orientation:landscape)_and_(max-height:560px)]:text-base dark:text-white">{title}</h1>
                        <p className="truncate text-[10px] font-medium text-slate-500 dark:text-slate-400">{settings.appName}</p>
                    </div>
                    <button
                        type="button"
                        onClick={onToggleDarkMode}
                        className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl touch-manipulation active:scale-95 [@media(orientation:landscape)_and_(max-height:560px)]:h-10 [@media(orientation:landscape)_and_(max-height:560px)]:w-10 ${
                            darkMode ? 'bg-slate-800 text-amber-300' : 'bg-slate-100 text-slate-700'
                        }`}
                        aria-label="ธีม"
                    >
                        {darkMode ? <Sun size={20} /> : <Moon size={20} />}
                    </button>
                </header>

                <main
                    className={`mobile-field-app min-h-0 flex-1 scroll-pb-[calc(5.75rem+env(safe-area-inset-bottom,0px))] overflow-y-auto overscroll-y-contain pt-3 ps-[max(0.75rem,env(safe-area-inset-left,0px))] pe-[max(0.75rem,env(safe-area-inset-right,0px))] [@media(orientation:landscape)_and_(max-height:560px)]:pt-2 [@media(orientation:landscape)_and_(max-height:560px)]:pb-[calc(4.75rem+env(safe-area-inset-bottom,0px))] ${mainBottomPad}`}
                    style={{ WebkitTapHighlightColor: 'transparent', overscrollBehaviorY: 'contain' }}
                >
                    {tab === 'home' && (
                        <DailyStepRecorder
                            mobileShell
                            employees={employees}
                            settings={settings}
                            transactions={transactions}
                            onSaveTransaction={onSaveTransaction}
                            onDeleteTransaction={onDeleteTransaction}
                            ensureEmployeeWage={ensureEmployeeWage}
                            setSettings={handleSetSettings}
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
                        <div className="space-y-3">
                            <div className="space-y-2">
                                <p className={`text-[11px] font-bold uppercase tracking-wide ${darkMode ? 'text-slate-500' : 'text-slate-400'}`}>ประเภท</p>
                                <div className="flex flex-wrap gap-2">
                                    {(
                                        [
                                            { type: null as const, label: 'ทั้งหมด' },
                                            { type: 'Income' as const, label: 'รายรับ' },
                                            { type: 'Expense' as const, label: 'รายจ่าย' },
                                        ] as const
                                    ).map(({ type: tType, label: tLabel }) => {
                                        const active = recordTypeFilter === tType;
                                        return (
                                            <button
                                                key={tLabel}
                                                type="button"
                                                onClick={() => {
                                                    setRecordTypeFilter(tType);
                                                    setRecordCatFilter(null);
                                                }}
                                                className={`min-h-[40px] shrink-0 rounded-full border px-4 text-xs font-bold touch-manipulation ${
                                                    active
                                                        ? 'border-emerald-600 bg-emerald-600 text-white dark:border-emerald-500 dark:bg-emerald-600'
                                                        : darkMode
                                                          ? 'border-transparent bg-slate-800/80 text-slate-300'
                                                          : 'border-transparent bg-white/90 text-slate-600 shadow-sm'
                                                }`}
                                            >
                                                {tLabel}
                                            </button>
                                        );
                                    })}
                                </div>
                            </div>
                            <div className="space-y-2">
                                <p className={`text-[11px] font-bold uppercase tracking-wide ${darkMode ? 'text-slate-500' : 'text-slate-400'}`}>หมวด</p>
                                <div className="flex gap-1.5 overflow-x-auto pb-1 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
                                    {recordFilterChips.map(key => {
                                        const active = (key || null) === (recordCatFilter || '');
                                        const label = !key ? 'ทุกหมวด' : CATEGORY_LABEL_TH[key] || key;
                                        return (
                                            <button
                                                key={key || 'all'}
                                                type="button"
                                                onClick={() => {
                                                    setRecordCatFilter(key || null);
                                                    setRecordTypeFilter(null);
                                                }}
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
                            <p className={`text-center text-[10px] font-medium leading-relaxed ${darkMode ? 'text-slate-600' : 'text-slate-400'}`}>
                                เวอร์ชัน {appVersion}
                                {latestVersionNote ? ` · ${latestVersionNote}` : ''}
                            </p>
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

                <nav
                    className="pointer-events-none fixed bottom-0 left-0 right-0 z-40 mx-auto max-w-full touch-manipulation sm:max-w-xl [@media(orientation:landscape)_and_(max-height:560px)]:sm:max-w-full"
                    aria-label="เมนูหลักมือถือ"
                    style={{
                        paddingBottom: 'max(0.5rem, env(safe-area-inset-bottom, 0px))',
                        paddingLeft: 'max(0.75rem, env(safe-area-inset-left, 0px))',
                        paddingRight: 'max(0.75rem, env(safe-area-inset-right, 0px))',
                    }}
                >
                    <div
                        className={`pointer-events-auto relative mx-auto w-full max-w-full overflow-hidden rounded-[1.25rem] border shadow-[0_-12px_40px_-16px_rgba(15,23,42,0.12),0_16px_48px_-20px_rgba(37,99,235,0.08)] backdrop-blur-2xl ${
                            darkMode
                                ? 'border-white/[0.09] bg-gradient-to-b from-slate-800/98 to-slate-900/[0.99] ring-1 ring-white/[0.07]'
                                : 'border-slate-200/80 bg-gradient-to-b from-white via-white to-slate-50/90 ring-1 ring-white/90'
                        }`}
                    >
                        <div
                            className={`pointer-events-none absolute inset-x-0 top-0 h-10 rounded-t-[1.25rem] opacity-90 ${
                                darkMode
                                    ? 'bg-gradient-to-b from-white/[0.06] to-transparent'
                                    : 'bg-gradient-to-b from-blue-100/35 via-white/40 to-transparent'
                            }`}
                            aria-hidden
                        />
                        <div
                            className="pointer-events-none absolute inset-x-6 top-0 z-[1] h-px bg-gradient-to-r from-transparent via-slate-300/50 to-transparent dark:via-white/12"
                            aria-hidden
                        />
                        <div className="relative z-10 flex items-stretch justify-between gap-1 px-1.5 py-2 [@media(orientation:landscape)_and_(max-height:560px)]:py-1.5" role="tablist">
                            {TAB_BAR.map(({ id, label, icon: Icon }) => {
                                const active = tab === id;
                                return (
                                    <button
                                        key={id}
                                        type="button"
                                        role="tab"
                                        aria-selected={active}
                                        aria-current={active ? 'page' : undefined}
                                        onClick={() => {
                                            setTab(id);
                                            if (id === 'more') setMorePanel('root');
                                            if (id === 'records') {
                                                setRecordCatFilter(null);
                                                setRecordTypeFilter(null);
                                            }
                                        }}
                                        className={`relative flex min-h-[60px] min-w-0 flex-1 flex-col items-center justify-center gap-1 rounded-2xl py-1.5 touch-manipulation transition-all duration-300 motion-reduce:transition-none motion-reduce:active:scale-100 active:scale-[0.97] [@media(orientation:landscape)_and_(max-height:560px)]:min-h-[52px] [@media(orientation:landscape)_and_(max-height:560px)]:py-1 ${
                                            active
                                                ? darkMode
                                                    ? 'bg-gradient-to-b from-blue-500/[0.16] to-indigo-500/[0.12] shadow-[inset_0_1px_0_rgba(255,255,255,0.08),0_8px_18px_-12px_rgba(37,99,235,0.75)] ring-1 ring-blue-400/30'
                                                    : 'bg-gradient-to-b from-blue-500/14 to-indigo-500/10 shadow-[inset_0_1px_0_rgba(255,255,255,0.68),0_10px_18px_-14px_rgba(37,99,235,0.45)] ring-1 ring-blue-500/20'
                                                : darkMode
                                                  ? 'ring-1 ring-transparent hover:bg-white/[0.045]'
                                                  : 'ring-1 ring-transparent hover:bg-slate-100/80'
                                        }`}
                                    >
                                        <span className="relative flex h-9 w-9 shrink-0 items-center justify-center [@media(orientation:landscape)_and_(max-height:560px)]:h-8 [@media(orientation:landscape)_and_(max-height:560px)]:w-8">
                                            {active ? (
                                                <span
                                                    className={`absolute inset-0 rounded-full bg-gradient-to-br shadow-lg motion-reduce:transition-none transition-transform duration-300 ease-out ${
                                                        darkMode
                                                            ? 'from-blue-500 to-indigo-600 shadow-black/40'
                                                            : 'from-blue-600 to-indigo-600 shadow-blue-600/35'
                                                    }`}
                                                />
                                            ) : null}
                                            <Icon
                                                size={20}
                                                strokeWidth={active ? 2.4 : 2}
                                                className={`relative z-10 shrink-0 transition-colors duration-300 ${
                                                    active ? 'text-white' : darkMode ? 'text-slate-400' : 'text-slate-500'
                                                }`}
                                            />
                                        </span>
                                        <span
                                            className={`h-0.5 w-5 shrink-0 rounded-full transition-colors duration-300 [@media(orientation:landscape)_and_(max-height:560px)]:w-4 ${
                                                active
                                                    ? 'bg-gradient-to-r from-blue-500 to-indigo-500 dark:from-blue-400 dark:to-indigo-400'
                                                    : darkMode
                                                      ? 'bg-slate-600/55'
                                                      : 'bg-slate-200/90'
                                            }`}
                                            aria-hidden
                                        />
                                        <span
                                            className={`max-w-[5rem] truncate px-0.5 text-center text-[11px] font-medium leading-tight tracking-normal transition-colors duration-300 [@media(orientation:landscape)_and_(max-height:560px)]:text-[10px] ${
                                                active
                                                    ? darkMode
                                                        ? 'text-slate-100'
                                                        : 'text-slate-800'
                                                    : darkMode
                                                      ? 'text-slate-400'
                                                      : 'text-slate-500'
                                            }`}
                                        >
                                            {label}
                                        </span>
                                    </button>
                                );
                            })}
                        </div>
                    </div>
                </nav>
            </div>
        </div>
    );
};

export default MobileFieldApp;
