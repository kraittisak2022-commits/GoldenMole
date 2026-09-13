import { useMemo } from 'react';
import { Clock, Truck } from 'lucide-react';
import type { Employee, Transaction } from '../../types';
import type { VehicleCatalogRow } from '../../utils/vehicleCatalog';
import { useShareLocale } from '../Share/shareI18n';
import { buildCountRecordSandUnit, buildCountRecordTripUnits } from './countRecordUtils';
import { buildMacroUsageSummary } from './dailyOpsCardUtils';
import { computeWorkSpan } from './countRecordAnalytics';
import ExcavatorIcon from './ExcavatorIcon';

interface DayOpsBriefProps {
    dayKey: string;
    transactions: Transaction[];
    employees: Employee[];
    vehicleCatalog?: VehicleCatalogRow[];
}

/** สรุปสั้นๆ สำหรับโหมด Real-time / แชร์: รถเที่ยว · แม็คโคร · เวลาเครื่องร่อน */
const DayOpsBrief = ({
    dayKey,
    transactions,
    employees,
    vehicleCatalog = [],
}: DayOpsBriefProps) => {
    const { t } = useShareLocale();

    const tripVehicleCount = useMemo(
        () => buildCountRecordTripUnits(dayKey, transactions, employees, vehicleCatalog).length,
        [dayKey, transactions, employees, vehicleCatalog],
    );

    const macroCount = useMemo(
        () => buildMacroUsageSummary(dayKey, transactions, employees, vehicleCatalog).vehicleCount,
        [dayKey, transactions, employees, vehicleCatalog],
    );

    const sandSpan = useMemo(() => {
        const sand = buildCountRecordSandUnit(dayKey, transactions);
        if (!sand || sand.lapTimes.length === 0) return null;
        return computeWorkSpan(sand.lapTimes, dayKey);
    }, [dayKey, transactions]);

    const sandTimeLabel = (() => {
        if (!sandSpan?.startClock) return t('sandMachineNoData');
        if (!sandSpan.endClock || sandSpan.startClock === sandSpan.endClock) {
            return t('sandMachineStartOnly', { start: sandSpan.startClock });
        }
        return t('sandMachineHours', { start: sandSpan.startClock, end: sandSpan.endClock });
    })();

    return (
        <div className="mb-3 rounded-2xl border border-slate-200/80 bg-gradient-to-br from-slate-50 to-indigo-50/40 p-3.5 shadow-sm dark:border-slate-700/60 dark:from-slate-900 dark:to-indigo-950/30 sm:p-4">
            <p className="mb-2.5 text-[11px] font-bold uppercase tracking-[0.14em] text-slate-500 dark:text-slate-400">
                {t('dayOpsBriefTitle')}
            </p>
            <ul className="grid gap-2.5 sm:grid-cols-3">
                <li className="flex items-start gap-2.5 rounded-xl border border-blue-200/60 bg-white/90 px-3 py-2.5 dark:border-blue-500/20 dark:bg-slate-900/70">
                    <span className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-blue-500/10 text-blue-600 dark:text-blue-400">
                        <Truck size={16} />
                    </span>
                    <div className="min-w-0">
                        <p className="text-[11px] font-semibold text-slate-500 dark:text-slate-400">{t('dayOpsTripVehicles')}</p>
                        <p className="text-sm font-bold text-slate-800 dark:text-slate-100">
                            {t('dayOpsTripVehiclesValue', { n: tripVehicleCount })}
                        </p>
                    </div>
                </li>
                <li className="flex items-start gap-2.5 rounded-xl border border-amber-200/60 bg-white/90 px-3 py-2.5 dark:border-amber-500/20 dark:bg-slate-900/70">
                    <span className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-amber-500/10 text-amber-600 dark:text-amber-400">
                        <ExcavatorIcon size={16} />
                    </span>
                    <div className="min-w-0">
                        <p className="text-[11px] font-semibold text-slate-500 dark:text-slate-400">{t('dayOpsMacroVehicles')}</p>
                        <p className="text-sm font-bold text-slate-800 dark:text-slate-100">
                            {t('dayOpsMacroVehiclesValue', { n: macroCount })}
                        </p>
                    </div>
                </li>
                <li className="flex items-start gap-2.5 rounded-xl border border-pink-200/60 bg-white/90 px-3 py-2.5 dark:border-pink-500/20 dark:bg-slate-900/70 sm:col-span-1">
                    <span className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-pink-500/10 text-pink-600 dark:text-pink-400">
                        <Clock size={16} />
                    </span>
                    <div className="min-w-0">
                        <p className="text-[11px] font-semibold text-slate-500 dark:text-slate-400">{t('dayOpsSandMachine')}</p>
                        <p className="text-sm font-bold text-slate-800 dark:text-slate-100">{sandTimeLabel}</p>
                    </div>
                </li>
            </ul>
        </div>
    );
};

export default DayOpsBrief;
