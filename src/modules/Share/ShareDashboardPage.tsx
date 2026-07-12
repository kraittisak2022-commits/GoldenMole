import { useCallback, useEffect, useMemo, useState } from 'react';
import { Radio, AlertCircle } from 'lucide-react';
import DashboardV4 from '../Dashboard/DashboardV4';
import SharePinGate from './SharePinGate';
import { fetchShareSettings, type DashboardShareSettings } from '../../services/shareService';
import { isShareSessionUnlocked } from '../../utils/shareAuth';
import { useShareTransactionsRealtime } from '../../hooks/useShareTransactionsRealtime';
import * as db from '../../services/dataService';
import type { Employee, AppSettings } from '../../types';
import { getFirstDayOfMonth, getToday } from '../../utils';

interface ShareDashboardPageProps {
    token: string;
}

const ShareDashboardPage = ({ token }: ShareDashboardPageProps) => {
    const [settings, setSettings] = useState<DashboardShareSettings | null>(null);
    const [settingsLoading, setSettingsLoading] = useState(true);
    const [settingsError, setSettingsError] = useState<string | null>(null);
    const [unlocked, setUnlocked] = useState(() => isShareSessionUnlocked(token));
    const [employees, setEmployees] = useState<Employee[]>([]);
    const [appSettings, setAppSettings] = useState<AppSettings | undefined>();

    const canLoadData = unlocked && !!settings?.enabled;

    const { transactions, loading: txLoading, refreshTransactions } = useShareTransactionsRealtime(canLoadData);

    useEffect(() => {
        let cancelled = false;
        void (async () => {
            setSettingsLoading(true);
            const data = await fetchShareSettings();
            if (cancelled) return;
            if (!data) {
                setSettingsError('ไม่พบการตั้งค่าการแชร์');
                setSettingsLoading(false);
                return;
            }
            if (!data.enabled) {
                setSettingsError('การแชร์ลิงก์ถูกปิดอยู่');
                setSettings(data);
                setSettingsLoading(false);
                return;
            }
            if (data.shareToken !== token) {
                setSettingsError('ลิงก์ไม่ถูกต้องหรือหมดอายุ');
                setSettingsLoading(false);
                return;
            }
            if (!data.pinHash) {
                setSettingsError('ยังไม่ได้ตั้งรหัส PIN');
                setSettings(data);
                setSettingsLoading(false);
                return;
            }
            setSettings(data);
            setSettingsError(null);
            setSettingsLoading(false);
        })();
        return () => {
            cancelled = true;
        };
    }, [token]);

    useEffect(() => {
        if (!canLoadData) return;
        let cancelled = false;
        void (async () => {
            const [emps, settingsData] = await Promise.all([db.fetchEmployees(), db.fetchSettings()]);
            if (cancelled) return;
            setEmployees(emps);
            if (settingsData) setAppSettings(settingsData);
        })();
        return () => {
            cancelled = true;
        };
    }, [canLoadData]);

    const dateFilter = useMemo(
        () => ({ start: getFirstDayOfMonth(), end: getToday() }),
        [],
    );

    const handleUnlocked = useCallback(() => {
        setUnlocked(true);
    }, []);

    if (settingsLoading) {
        return (
            <div className="flex min-h-[100dvh] items-center justify-center bg-slate-950 text-white">
                <p className="text-sm font-medium text-slate-300">กำลังโหลด...</p>
            </div>
        );
    }

    if (settingsError) {
        return (
            <div className="flex min-h-[100dvh] items-center justify-center bg-gradient-to-br from-slate-950 via-slate-900 to-indigo-950 px-4">
                <div className="max-w-sm rounded-2xl border border-white/10 bg-white/95 p-6 text-center shadow-xl">
                    <AlertCircle className="mx-auto text-rose-500" size={32} />
                    <h1 className="mt-3 text-lg font-bold text-slate-900">ไม่สามารถเปิดแดชบอร์ดได้</h1>
                    <p className="mt-2 text-sm text-slate-600">{settingsError}</p>
                </div>
            </div>
        );
    }

    if (!unlocked && settings) {
        return <SharePinGate token={token} pinHash={settings.pinHash} onUnlocked={handleUnlocked} />;
    }

    return (
        <div className="min-h-[100dvh] bg-slate-100 px-3 py-safe-top pb-safe-bottom pt-3 sm:px-4 sm:py-4">
            <div className="mx-auto max-w-6xl">
                <div className="mb-3 flex items-center justify-between gap-2 rounded-2xl border border-indigo-200/60 bg-indigo-50/80 px-3 py-2 sm:px-4">
                    <div className="flex items-center gap-2 min-w-0">
                        <Radio size={16} className="shrink-0 text-indigo-600" />
                        <p className="truncate text-xs font-semibold text-indigo-900 sm:text-sm">
                            โหมดดูแบบ Real-time — อัปเดตอัตโนมัติ
                        </p>
                    </div>
                    {txLoading && (
                        <span className="shrink-0 text-[10px] font-medium text-indigo-600 sm:text-xs">กำลังโหลด...</span>
                    )}
                </div>

                <DashboardV4
                    transactions={transactions}
                    dateFilter={dateFilter}
                    employees={employees}
                    settings={appSettings}
                    onRefreshTransactions={refreshTransactions}
                    shareMode
                    hideFinancial={!settings?.showFinancial}
                />
            </div>
        </div>
    );
};

export default ShareDashboardPage;
