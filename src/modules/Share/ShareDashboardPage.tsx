import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Radio, AlertCircle } from 'lucide-react';
import DashboardV4 from '../Dashboard/DashboardV4';
import SharePinGate from './SharePinGate';
import { SharePreferenceControls, SharePreferencesProvider, useShareLocale, type ShareMessageKey } from './shareI18n';
import { fetchShareSettings, type DashboardShareSettings } from '../../services/shareService';
import {
    getShareDeviceLabel,
    recordShareVisit,
    saveViewerDeviceLabel,
} from '../../services/shareVisitService';
import { isShareSessionUnlocked } from '../../utils/shareAuth';
import { useShareTransactionsRealtime } from '../../hooks/useShareTransactionsRealtime';
import * as db from '../../services/dataService';
import type { Employee, AppSettings } from '../../types';
import { getFirstDayOfMonth, getToday } from '../../utils';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';

interface ShareDashboardPageProps {
    token: string;
}

const ShareDashboardContent = ({ token }: ShareDashboardPageProps) => {
    const { t } = useShareLocale();
    const [settings, setSettings] = useState<DashboardShareSettings | null>(null);
    const [settingsLoading, setSettingsLoading] = useState(true);
    const [settingsErrorKey, setSettingsErrorKey] = useState<ShareMessageKey | null>(null);
    const [unlocked, setUnlocked] = useState(() => isShareSessionUnlocked(token));
    const [employees, setEmployees] = useState<Employee[]>([]);
    const [appSettings, setAppSettings] = useState<AppSettings | undefined>();
    const [deviceName, setDeviceName] = useState(() => getShareDeviceLabel());
    const [deviceNameMsg, setDeviceNameMsg] = useState<string | null>(null);
    const [savingDeviceName, setSavingDeviceName] = useState(false);
    const visitLoggedRef = useRef(false);

    const canLoadData = unlocked && !!settings?.enabled;

    const { transactions, loading: txLoading, refreshTransactions } = useShareTransactionsRealtime(canLoadData);

    useEffect(() => {
        let cancelled = false;
        void (async () => {
            setSettingsLoading(true);
            const data = await fetchShareSettings();
            if (cancelled) return;
            if (!data) {
                setSettingsErrorKey('shareNotFound');
                setSettingsLoading(false);
                return;
            }
            if (!data.enabled) {
                setSettingsErrorKey('shareDisabled');
                setSettings(data);
                setSettingsLoading(false);
                return;
            }
            if (data.shareToken !== token) {
                setSettingsErrorKey('invalidLink');
                setSettingsLoading(false);
                return;
            }
            if (!data.pinHash) {
                setSettingsErrorKey('pinNotSet');
                setSettings(data);
                setSettingsLoading(false);
                return;
            }
            setSettings(data);
            setSettingsErrorKey(null);
            setSettingsLoading(false);
        })();
        return () => {
            cancelled = true;
        };
    }, [token]);

    const settingsError = settingsErrorKey ? t(settingsErrorKey) : null;

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

    useEffect(() => {
        if (!canLoadData || visitLoggedRef.current) return;
        visitLoggedRef.current = true;
        void recordShareVisit(token);
    }, [canLoadData, token]);

    const dateFilter = useMemo(
        () => ({ start: getFirstDayOfMonth(), end: getToday() }),
        [],
    );

    const handleUnlocked = useCallback(() => {
        setUnlocked(true);
    }, []);

    const handleSaveDeviceName = async () => {
        setSavingDeviceName(true);
        const ok = await saveViewerDeviceLabel(token, deviceName);
        setSavingDeviceName(false);
        setDeviceNameMsg(ok ? t('deviceNameSaved') : null);
        if (ok) window.setTimeout(() => setDeviceNameMsg(null), 2000);
    };

    if (settingsLoading) {
        return (
            <div className="flex min-h-[100dvh] items-center justify-center bg-slate-100 text-slate-900 dark:bg-slate-950 dark:text-white">
                <p className="text-sm font-medium text-slate-500 dark:text-slate-300">{t('loading')}</p>
            </div>
        );
    }

    if (settingsErrorKey) {
        return (
            <div className="flex min-h-[100dvh] items-center justify-center bg-gradient-to-br from-slate-100 via-slate-50 to-indigo-50 px-4 dark:from-slate-950 dark:via-slate-900 dark:to-indigo-950">
                <div className="max-w-sm rounded-2xl border border-slate-200/80 bg-white/95 p-6 text-center shadow-xl dark:border-white/10 dark:bg-slate-900/90">
                    <AlertCircle className="mx-auto text-rose-500" size={32} />
                    <h1 className="mt-3 text-lg font-bold text-slate-900 dark:text-white">{t('cannotOpenDashboard')}</h1>
                    <p className="mt-2 text-sm text-slate-600 dark:text-slate-400">{settingsError}</p>
                    <div className="mt-4 flex justify-center">
                        <SharePreferenceControls />
                    </div>
                </div>
            </div>
        );
    }

    if (!unlocked && settings) {
        return <SharePinGate token={token} pinHash={settings.pinHash} onUnlocked={handleUnlocked} />;
    }

    return (
        <div className="min-h-[100dvh] bg-slate-100 px-3 py-safe-top pb-safe-bottom pt-3 dark:bg-slate-950 sm:px-4 sm:py-4">
            <div className="mx-auto max-w-6xl">
                <div className="mb-3 flex items-center justify-between gap-2 rounded-2xl border border-indigo-200/60 bg-indigo-50/80 px-3 py-2 dark:border-indigo-500/20 dark:bg-indigo-500/10 sm:px-4">
                    <div className="flex min-w-0 items-center gap-2">
                        <Radio size={16} className="shrink-0 text-indigo-600 dark:text-indigo-400" />
                        <p className="truncate text-xs font-semibold text-indigo-900 dark:text-indigo-100 sm:text-sm">
                            {t('realtimeBanner')}
                        </p>
                    </div>
                    <div className="flex shrink-0 items-center gap-2">
                        {txLoading && (
                            <span className="text-[10px] font-medium text-indigo-600 dark:text-indigo-300 sm:text-xs">
                                {t('loading')}
                            </span>
                        )}
                        <SharePreferenceControls />
                    </div>
                </div>

                <div className="mb-3 rounded-2xl border border-slate-200 bg-white px-3 py-2.5 dark:border-white/10 dark:bg-slate-900 sm:px-4">
                    <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wide text-slate-400">
                        {t('deviceNameLabel')}
                    </p>
                    <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
                        <Input
                            value={deviceName}
                            onChange={(e) => setDeviceName(e.target.value.slice(0, 60))}
                            placeholder={t('deviceNamePlaceholder')}
                            className="flex-1 text-sm"
                        />
                        <Button
                            className="shrink-0"
                            onClick={() => void handleSaveDeviceName()}
                            disabled={savingDeviceName}
                        >
                            {t('deviceNameSave')}
                        </Button>
                    </div>
                    {deviceNameMsg ? (
                        <p className="mt-1.5 text-xs font-medium text-emerald-600 dark:text-emerald-400">{deviceNameMsg}</p>
                    ) : null}
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

const ShareDashboardPage = ({ token }: ShareDashboardPageProps) => (
    <SharePreferencesProvider>
        <ShareDashboardContent token={token} />
    </SharePreferencesProvider>
);

export default ShareDashboardPage;
