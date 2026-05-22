import { ChevronLeft } from 'lucide-react';
import type { AppSettings, Employee, Transaction } from '../../types';
import type { DailyModuleDef } from './mobileDailyModules';
import { routeForDailyModule } from './androidModuleRoutes';
import DailyStepRecorder from '../Dashboard/DailyStepRecorder';
import LaborModule from '../Labor/LaborModule';

type MobileQuickInputSheetProps = {
    module: DailyModuleDef;
    selectedDate: string;
    employees: Employee[];
    settings: AppSettings;
    transactions: Transaction[];
    touchLayout?: boolean;
    onClose: () => void;
    onSaveTransaction: (t: Transaction) => void;
    onDeleteTransaction: (id: string) => void;
    onPermanentDeleteTransaction?: (id: string) => void | Promise<void>;
    ensureEmployeeWage: (emp: Employee) => Promise<number>;
    handleSetSettings: (updater: AppSettings | ((prev: AppSettings) => AppSettings)) => void;
    handleSetTransactions: (updater: Transaction[] | ((prev: Transaction[]) => Transaction[])) => void;
};

const MobileQuickInputSheet = ({
    module,
    selectedDate,
    employees,
    settings,
    transactions,
    touchLayout = true,
    onClose,
    onSaveTransaction,
    onDeleteTransaction,
    onPermanentDeleteTransaction,
    ensureEmployeeWage,
    handleSetSettings,
    handleSetTransactions,
}: MobileQuickInputSheetProps) => {
    const route = routeForDailyModule(module);

    return (
        <div className="mobile-android-quick-input fixed inset-0 z-50 flex flex-col bg-[#F3FBFC]">
            <header
                className="sticky top-0 z-10 flex items-center gap-2 border-b border-[#E7ECF3] bg-white/95 px-3 py-2.5 backdrop-blur-md"
                style={{ paddingTop: 'max(0.5rem, env(safe-area-inset-top, 0px))' }}
            >
                <button
                    type="button"
                    onClick={onClose}
                    className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-[#F5F8FC] text-[#1A2433] touch-manipulation active:scale-95"
                    aria-label="กลับ"
                >
                    <ChevronLeft size={22} strokeWidth={2.5} />
                </button>
                <div className="min-w-0 flex-1">
                    <h1 className="truncate text-base font-bold text-[#1A2433]">{module.quickInputTitle}</h1>
                    <p className="truncate text-xs text-[#6B7788]">{selectedDate}</p>
                </div>
            </header>
            <main
                className="mobile-field-app min-h-0 flex-1 overflow-y-auto overscroll-y-contain px-3 py-3"
                style={{
                    paddingBottom: 'max(1rem, env(safe-area-inset-bottom, 0px))',
                    WebkitTapHighlightColor: 'transparent',
                }}
            >
                {route.type === 'labor' ? (
                    <div className="rounded-3xl border border-[#E7ECF3] bg-white p-3 shadow-sm">
                        <LaborModule
                            employees={employees}
                            settings={settings}
                            onSaveTransaction={onSaveTransaction}
                            onDeleteTransaction={onDeleteTransaction}
                            transactions={transactions}
                            setTransactions={handleSetTransactions}
                            ensureEmployeeWage={ensureEmployeeWage}
                            initialTab={route.tab}
                            fixedDate={selectedDate}
                            compactShell
                        />
                    </div>
                ) : (
                    <DailyStepRecorder
                        mobileShell
                        touchLayout={touchLayout}
                        singleStepMode={route.step}
                        hideReportMode
                        employees={employees}
                        settings={settings}
                        transactions={transactions}
                        initialDate={selectedDate}
                        initialStep={route.step}
                        onSaveTransaction={onSaveTransaction}
                        onDeleteTransaction={onDeleteTransaction}
                        onPermanentDeleteTransaction={onPermanentDeleteTransaction}
                        ensureEmployeeWage={ensureEmployeeWage}
                        setSettings={handleSetSettings}
                    />
                )}
            </main>
        </div>
    );
};

export default MobileQuickInputSheet;
