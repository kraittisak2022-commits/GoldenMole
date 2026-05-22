import { lazy, Suspense, useState, useCallback, useEffect, useRef } from 'react';
import {
    ChevronLeft,
    ChevronRight,
    Users,
    List,
    FolderKanban,
    Settings,
    Shield,
    Monitor,
    User,
    LogOut,
} from 'lucide-react';
import {
    AppSettings,
    Employee,
    Transaction,
    LandProject,
    AdminUser,
    AdminUiTheme,
    AdminLog,
} from '../../types';
import type { AppLocale } from '../../utils/i18n';
import { getToday } from '../../utils';
import type { OfflineSyncSnapshot } from '../../services/offlineSync';
import type { OfflineQueueItem } from '../../services/offlineSync';
import SettingsModule from '../Settings/SettingsModule';
import CalendarView from '../Dashboard/CalendarView';
import EmployeeManager from '../Employees/EmployeeManager';
import LandModule from '../Land/LandModule';
import MobileNavRail from './MobileNavRail';
import MobileAndroidHome from './MobileAndroidHome';
import MobileQuickInputSheet from './MobileQuickInputSheet';
import type { DailyModuleDef } from './mobileDailyModules';

const RecordManager = lazy(() => import('../DataList/RecordManager'));
const AdminModule = lazy(() => import('../Admin/AdminModule'));

const NAV_RAIL_PREF = 'cm_mobile_nav_rail_open_v1';

type SurfacePage = 'home' | 'calendar' | 'settings' | 'employees' | 'transactions' | 'projects' | 'sync' | 'admin';

interface MobileFieldAppProps {
    settings: AppSettings;
    employees: Employee[];
    transactions: Transaction[];
    projects: LandProject[];
    admins: AdminUser[];
    adminLogs: AdminLog[];
    currentAdmin: AdminUser;
    appVersion: string;
    latestVersionNote: string;
    autoVersionNotes: string[];
    appIcon: string;
    darkMode: boolean;
    locale: AppLocale;
    financialMaskEnabled?: boolean;
    touchLayout?: boolean;
    onToggleDarkMode: () => void;
    onToggleLocale: () => void;
    onLogout: () => void;
    onSwitchToDesktop: () => void;
    onOpenAccount: () => void;
    onSaveTransaction: (t: Transaction) => void;
    onDeleteTransaction: (id: string) => void;
    onPermanentDeleteTransaction?: (id: string) => void | Promise<void>;
    handleSetTransactions: (updater: Transaction[] | ((prev: Transaction[]) => Transaction[])) => void;
    handleSetEmployees: (updater: Employee[] | ((prev: Employee[]) => Employee[])) => void;
    handleSetProjects: (updater: LandProject[] | ((prev: LandProject[]) => LandProject[])) => void;
    onSave: (t: Transaction) => void;
    ensureEmployeeWage: (emp: Employee) => Promise<number>;
    handleSetSettings: (updater: AppSettings | ((prev: AppSettings) => AppSettings)) => void;
    handleSetAdmins: (updater: AdminUser[] | ((prev: AdminUser[]) => AdminUser[])) => void;
    onUpdateAdminProfile: (updates: {
        displayName?: string;
        avatar?: string;
        uiTheme?: AdminUiTheme;
        currentPassword?: string;
        newPassword?: string;
    }) => Promise<{ ok: boolean; message?: string }>;
    addLog: (action: string, details: string) => void;
    offlineSync: OfflineSyncSnapshot;
    offlineQueueItems: OfflineQueueItem[];
    onRetrySync: () => void;
    onDropQueueItem: (queueId: string) => void;
    onRetryQueueItem: (queueId: string) => void;
    onResolveConflictUseLocal: (queueId: string) => void;
    onResolveConflictUseServer: (queueId: string) => void;
    canInstallPwa: boolean;
    onInstallPwa: () => void;
    mobilePinEnabled: boolean;
    onSetupMobilePin: () => void;
    onDisableMobilePin: () => void;
}

const MobileFieldApp = (props: MobileFieldAppProps) => {
    const {
        settings,
        employees,
        transactions,
        projects,
        admins,
        adminLogs,
        currentAdmin,
        appVersion,
        latestVersionNote,
        autoVersionNotes,
        appIcon,
        touchLayout = false,
        financialMaskEnabled = false,
        onToggleDarkMode,
        onToggleLocale,
        onLogout,
        onSwitchToDesktop,
        onOpenAccount,
        onSaveTransaction,
        onDeleteTransaction,
        onPermanentDeleteTransaction,
        handleSetTransactions,
        handleSetEmployees,
        handleSetProjects,
        onSave,
        ensureEmployeeWage,
        handleSetSettings,
        handleSetAdmins,
        onUpdateAdminProfile,
        addLog,
        offlineSync,
        offlineQueueItems,
        onRetrySync,
        onDropQueueItem,
        onRetryQueueItem,
        onResolveConflictUseLocal,
        onResolveConflictUseServer,
        canInstallPwa,
        onInstallPwa,
        mobilePinEnabled,
        onSetupMobilePin,
        onDisableMobilePin,
    } = props;

    const [page, setPage] = useState<SurfacePage>('home');
    const [navRailOpen, setNavRailOpen] = useState(true);
    const [selectedDate, setSelectedDate] = useState(getToday);
    const [activeModule, setActiveModule] = useState<DailyModuleDef | null>(null);
    const [refreshKey, setRefreshKey] = useState(0);
    const edgeSwipeRef = useRef(0);
    const navIntroTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    const dateInputRef = useRef<HTMLInputElement>(null);

    const lazyFallback = (
        <div className="rounded-3xl border border-[#E7ECF3] bg-white p-4 animate-pulse">
            <div className="h-4 w-24 rounded bg-slate-200" />
            <div className="mt-3 h-3 w-full rounded bg-slate-100" />
        </div>
    );

    useEffect(() => {
        try {
            const stored = localStorage.getItem(NAV_RAIL_PREF);
            if (stored === '0') setNavRailOpen(false);
        } catch {
            /* ignore */
        }
        navIntroTimerRef.current = setTimeout(() => {
            setNavRailOpen(false);
            try {
                localStorage.setItem(NAV_RAIL_PREF, '0');
            } catch {
                /* ignore */
            }
        }, 3000);
        return () => {
            if (navIntroTimerRef.current) clearTimeout(navIntroTimerRef.current);
        };
    }, []);

    const persistNavRail = useCallback((open: boolean) => {
        try {
            localStorage.setItem(NAV_RAIL_PREF, open ? '1' : '0');
        } catch {
            /* ignore */
        }
    }, []);

    const toggleNavRail = useCallback(() => {
        if (navIntroTimerRef.current) clearTimeout(navIntroTimerRef.current);
        setNavRailOpen(prev => {
            const next = !prev;
            persistNavRail(next);
            return next;
        });
    }, [persistNavRail]);

    const onPickDay = useCallback(() => {
        const el = dateInputRef.current;
        if (!el) return;
        if (typeof el.showPicker === 'function') el.showPicker();
        else el.click();
    }, []);

    const onRefresh = useCallback(() => {
        setRefreshKey(k => k + 1);
    }, []);

    const goHome = useCallback(() => {
        setPage('home');
        setActiveModule(null);
    }, []);

    const pageTitle =
        page === 'calendar'
            ? 'ปฏิทิน'
            : page === 'settings'
              ? 'ตั้งค่า'
              : page === 'employees'
                ? 'พนักงาน'
                : page === 'transactions'
                  ? 'รายการธุรกรรม'
                  : page === 'projects'
                    ? 'โครงการ'
                    : page === 'sync'
                      ? 'ศูนย์ซิงก์'
                      : page === 'admin'
                        ? 'จัดการแอดมิน'
                        : '';

    const showSubPageHeader = page !== 'home';

    return (
        <div
            className="mobile-shell-root mobile-android-shell relative flex min-h-[100dvh] w-full overflow-hidden bg-[#F3FBFC] font-sans touch-manipulation"
            style={{ overscrollBehaviorY: 'none' }}
        >
            <input
                ref={dateInputRef}
                type="date"
                className="sr-only"
                tabIndex={-1}
                aria-hidden
                value={selectedDate}
                onChange={e => setSelectedDate(e.target.value.slice(0, 10))}
            />

            {activeModule && (
                <MobileQuickInputSheet
                    module={activeModule}
                    selectedDate={selectedDate}
                    employees={employees}
                    settings={settings}
                    transactions={transactions}
                    touchLayout={touchLayout}
                    onClose={() => setActiveModule(null)}
                    onSaveTransaction={onSaveTransaction}
                    onDeleteTransaction={onDeleteTransaction}
                    onPermanentDeleteTransaction={onPermanentDeleteTransaction}
                    ensureEmployeeWage={ensureEmployeeWage}
                    handleSetSettings={handleSetSettings}
                    handleSetTransactions={handleSetTransactions}
                />
            )}

            <div className="relative mx-auto flex min-h-0 w-full max-w-full flex-1">
                <div
                    className={`shrink-0 overflow-hidden transition-[width] duration-300 ease-out ${
                        navRailOpen ? 'w-[72px]' : 'w-0'
                    }`}
                >
                    <MobileNavRail
                        open={navRailOpen}
                        homeSelected={page === 'home'}
                        onHome={goHome}
                        onCalendar={() => {
                            setPage('calendar');
                            setActiveModule(null);
                        }}
                        onSettings={() => {
                            setPage('settings');
                            setActiveModule(null);
                        }}
                        onToggleRail={toggleNavRail}
                        onLogout={onLogout}
                    />
                </div>

                <div className="relative flex min-h-0 min-w-0 flex-1 flex-col">
                    {!navRailOpen && (
                        <button
                            type="button"
                            onClick={toggleNavRail}
                            className="absolute left-0 top-1/2 z-20 flex -translate-y-1/2 items-center rounded-r-2xl border border-slate-200 bg-white py-4 pl-1 pr-1.5 shadow-md touch-manipulation active:scale-95"
                            aria-label="เปิดเมนู"
                        >
                            <ChevronRight size={20} className="text-[#546E7A]" />
                        </button>
                    )}

                    <div
                        className="absolute left-0 top-0 bottom-0 z-10 w-9"
                        aria-hidden={navRailOpen}
                        onPointerDown={() => {
                            edgeSwipeRef.current = 0;
                        }}
                        onPointerMove={e => {
                            if (navRailOpen || e.clientX > 36) return;
                            if (e.movementX > 0) edgeSwipeRef.current += e.movementX;
                            if (edgeSwipeRef.current >= 56) {
                                edgeSwipeRef.current = 0;
                                setNavRailOpen(true);
                                persistNavRail(true);
                            }
                        }}
                        onPointerUp={() => {
                            edgeSwipeRef.current = 0;
                        }}
                    />

                    {showSubPageHeader && (
                        <header
                            className="sticky top-0 z-10 flex items-center gap-2 border-b border-[#E7ECF3] bg-white/95 px-3 py-2.5 backdrop-blur-md"
                            style={{ paddingTop: 'max(0.5rem, env(safe-area-inset-top, 0px))' }}
                        >
                            <button
                                type="button"
                                onClick={goHome}
                                className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-[#F5F8FC] touch-manipulation active:scale-95"
                                aria-label="กลับหน้าแรก"
                            >
                                <ChevronLeft size={22} strokeWidth={2.5} />
                            </button>
                            <h1 className="min-w-0 flex-1 truncate text-lg font-bold text-[#1A2433]">{pageTitle}</h1>
                        </header>
                    )}

                    <main
                        className="min-h-0 flex-1 overflow-y-auto overscroll-y-contain"
                        style={{
                            paddingBottom: 'max(0.75rem, env(safe-area-inset-bottom, 0px))',
                            WebkitTapHighlightColor: 'transparent',
                        }}
                    >
                        {page === 'home' && (
                            <MobileAndroidHome
                                key={refreshKey}
                                settings={settings}
                                appIcon={appIcon}
                                selectedDate={selectedDate}
                                transactions={transactions}
                                employees={employees}
                                serverOnline={offlineSync.lastMessage !== 'ออฟไลน์'}
                                onPickDay={onPickDay}
                                onRefresh={onRefresh}
                                onOpenModule={setActiveModule}
                            />
                        )}

                        {page === 'calendar' && (
                            <div className="p-3">
                                <div className="rounded-3xl border border-[#E7ECF3] bg-white p-3 shadow-sm">
                                    <CalendarView
                                        transactions={transactions}
                                        employees={employees}
                                        onSaveTransaction={onSaveTransaction}
                                        onDeleteTransaction={onDeleteTransaction}
                                    />
                                </div>
                            </div>
                        )}

                        {page === 'settings' && (
                            <div className="space-y-3 p-3">
                                {[
                                    { key: 'account', icon: User, title: 'บัญชีแอดมิน', sub: currentAdmin.displayName, onClick: onOpenAccount },
                                    { key: 'employees', icon: Users, title: 'พนักงาน', sub: 'จัดการรายชื่อพนักงาน', onClick: () => setPage('employees') },
                                    { key: 'transactions', icon: List, title: 'รายการธุรกรรม', sub: 'ดูและจัดการรายการ', onClick: () => setPage('transactions') },
                                    { key: 'projects', icon: FolderKanban, title: 'โครงการ', sub: 'ที่ดิน / โครงการ', onClick: () => setPage('projects') },
                                ].map(row => (
                                    <button
                                        key={row.key}
                                        type="button"
                                        onClick={row.onClick}
                                        className="flex w-full items-center gap-4 rounded-3xl border border-[#E7ECF3] bg-white p-4 text-left shadow-sm touch-manipulation active:scale-[0.99]"
                                    >
                                        <row.icon className="h-6 w-6 shrink-0 text-[#00897B]" />
                                        <div className="min-w-0 flex-1">
                                            <p className="font-bold text-[#1A2433]">{row.title}</p>
                                            <p className="truncate text-xs text-[#6B7788]">{row.sub}</p>
                                        </div>
                                        <ChevronRight className="h-5 w-5 text-slate-400" />
                                    </button>
                                ))}
                                <div className="rounded-3xl border border-[#E7ECF3] bg-white p-3 shadow-sm">
                                    <SettingsModule
                                        settings={settings}
                                        setSettings={handleSetSettings}
                                        backupPayload={{
                                            employees,
                                            transactions,
                                            projects,
                                            admins,
                                            adminLogs,
                                        }}
                                        autoVersionNotes={autoVersionNotes}
                                        currentAdmin={currentAdmin}
                                        onUpdateAdminProfile={onUpdateAdminProfile}
                                    />
                                </div>
                                <div className="grid grid-cols-2 gap-2">
                                    <button type="button" onClick={onToggleLocale} className="min-h-[44px] rounded-2xl border border-[#E7ECF3] bg-white text-sm font-semibold text-[#1A2433]">
                                        ภาษา
                                    </button>
                                    <button type="button" onClick={onToggleDarkMode} className="min-h-[44px] rounded-2xl border border-[#E7ECF3] bg-white text-sm font-semibold text-[#1A2433]">
                                        ธีม
                                    </button>
                                </div>
                                {currentAdmin.role === 'SuperAdmin' && (
                                    <button
                                        type="button"
                                        onClick={() => setPage('admin')}
                                        className="flex w-full items-center gap-4 rounded-3xl border border-[#E7ECF3] bg-white p-4 text-left shadow-sm"
                                    >
                                        <Shield className="h-6 w-6 text-[#00897B]" />
                                        <span className="font-bold">จัดการแอดมิน</span>
                                    </button>
                                )}
                                <button
                                    type="button"
                                    onClick={() => setPage('sync')}
                                    className="flex w-full items-center gap-4 rounded-3xl border border-[#E7ECF3] bg-white p-4 text-left shadow-sm"
                                >
                                    <List className="h-6 w-6 text-[#00897B]" />
                                    <div>
                                        <p className="font-bold">ศูนย์ซิงก์ข้อมูล</p>
                                        <p className="text-xs text-[#6B7788]">{offlineSync.lastMessage} · ค้าง {offlineSync.queueSize}</p>
                                    </div>
                                </button>
                                <button type="button" onClick={mobilePinEnabled ? onDisableMobilePin : onSetupMobilePin} className="w-full rounded-2xl border border-[#E7ECF3] bg-white px-4 py-3 text-sm font-semibold">
                                    PIN lock: {mobilePinEnabled ? 'เปิด' : 'ปิด'}
                                </button>
                                {canInstallPwa && (
                                    <button type="button" onClick={onInstallPwa} className="w-full rounded-2xl border border-blue-200 bg-blue-50 px-4 py-3 text-sm font-bold text-blue-800">
                                        ติดตั้งเป็นแอป (PWA)
                                    </button>
                                )}
                                <button type="button" onClick={onSwitchToDesktop} className="flex w-full items-center justify-center gap-2 rounded-2xl border border-blue-200 bg-blue-50 py-3 text-sm font-bold text-blue-800">
                                    <Monitor size={18} />
                                    เว็บแอปปกติ
                                </button>
                                <button type="button" onClick={onLogout} className="flex w-full items-center justify-center gap-2 rounded-2xl border-2 border-red-300 bg-red-50 py-3 font-bold text-red-700">
                                    <LogOut size={18} />
                                    ออกจากระบบ
                                </button>
                                <p className="text-center text-[10px] text-[#94A3B8]">
                                    เวอร์ชัน {appVersion}
                                    {latestVersionNote ? ` · ${latestVersionNote}` : ''}
                                </p>
                            </div>
                        )}

                        {page === 'employees' && (
                            <div className="p-3">
                                <EmployeeManager
                                    employees={employees}
                                    setEmployees={handleSetEmployees}
                                    transactions={transactions}
                                    setTransactions={handleSetTransactions}
                                    settings={settings}
                                    setSettings={handleSetSettings}
                                />
                            </div>
                        )}

                        {page === 'transactions' && (
                            <div className="p-3">
                                <Suspense fallback={lazyFallback}>
                                    <RecordManager
                                        compact
                                        darkMode={false}
                                        amountMode={financialMaskEnabled ? 'percent' : 'currency'}
                                        transactions={transactions}
                                        onDeleteTransaction={onDeleteTransaction}
                                    />
                                </Suspense>
                            </div>
                        )}

                        {page === 'projects' && (
                            <div className="p-3">
                                <LandModule
                                    projects={projects}
                                    setProjects={handleSetProjects}
                                    onSave={onSave}
                                    transactions={transactions}
                                />
                            </div>
                        )}

                        {page === 'sync' && (
                            <div className="space-y-3 p-3">
                                <div className="rounded-3xl border border-[#E7ECF3] bg-white p-4 shadow-sm">
                                    <div className="flex items-center justify-between">
                                        <p className="text-sm font-bold">สถานะ: {offlineSync.lastMessage}</p>
                                        <button type="button" onClick={onRetrySync} className="rounded-xl bg-[#11A8BA] px-3 py-2 text-xs font-bold text-white">
                                            ซิงก์ใหม่
                                        </button>
                                    </div>
                                    <p className="mt-2 text-xs text-[#6B7788]">
                                        ค้าง {offlineSync.queueSize} · conflict {offlineSync.conflictCount}
                                    </p>
                                    <div className="mt-3 space-y-2">
                                        {offlineQueueItems.length === 0 ? (
                                            <p className="rounded-xl border border-[#E7ECF3] p-3 text-sm text-[#6B7788]">ไม่มีรายการค้าง</p>
                                        ) : (
                                            offlineQueueItems.map(item => (
                                                <div key={item.id} className="rounded-xl border border-[#E7ECF3] p-3 text-xs">
                                                    <p className="font-semibold">{item.tx.category}/{item.tx.subCategory || '-'}</p>
                                                    <p className="mt-1 text-[#6B7788]">{item.tx.description || '-'}</p>
                                                    <div className="mt-2 flex flex-wrap gap-2">
                                                        <button type="button" onClick={() => onRetryQueueItem(item.id)} className="rounded-lg bg-sky-600 px-2 py-1 font-bold text-white">retry</button>
                                                        {item.conflictWithId && (
                                                            <>
                                                                <button type="button" onClick={() => onResolveConflictUseLocal(item.id)} className="rounded-lg bg-emerald-600 px-2 py-1 font-bold text-white">เครื่อง</button>
                                                                <button type="button" onClick={() => onResolveConflictUseServer(item.id)} className="rounded-lg bg-amber-600 px-2 py-1 font-bold text-white">เซิร์ฟเวอร์</button>
                                                            </>
                                                        )}
                                                        <button type="button" onClick={() => onDropQueueItem(item.id)} className="rounded-lg bg-rose-600 px-2 py-1 font-bold text-white">ลบคิว</button>
                                                    </div>
                                                </div>
                                            ))
                                        )}
                                    </div>
                                </div>
                            </div>
                        )}

                        {page === 'admin' && currentAdmin.role === 'SuperAdmin' && (
                            <div className="p-3">
                                <Suspense fallback={lazyFallback}>
                                    <AdminModule
                                        admins={admins}
                                        setAdmins={handleSetAdmins}
                                        currentAdmin={currentAdmin}
                                        logs={adminLogs}
                                        addLog={addLog}
                                    />
                                </Suspense>
                            </div>
                        )}
                    </main>
                </div>
            </div>
        </div>
    );
};

export default MobileFieldApp;
