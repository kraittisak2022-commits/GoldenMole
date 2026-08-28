import { useMemo } from 'react';
import { Tractor, Users } from 'lucide-react';
import type { Employee, Transaction } from '../../types';
import type { VehicleCatalogRow } from '../../utils/vehicleCatalog';
import { useShareLocale } from '../Share/shareI18n';
import { formatDashboardMetric } from './countRecordUtils';
import { buildAttendanceSummary, buildMacroUsageSummary } from './dailyOpsCardUtils';

interface DailyOpsCardsProps {
    dayKey: string;
    transactions: Transaction[];
    employees: Employee[];
    shareMode?: boolean;
    vehicleCatalog?: VehicleCatalogRow[];
}

const DailyOpsCards = ({
    dayKey,
    transactions,
    employees,
    shareMode = false,
    vehicleCatalog = [],
}: DailyOpsCardsProps) => {
    const { t } = useShareLocale();

    const macroSummary = useMemo(
        () => buildMacroUsageSummary(dayKey, transactions, employees, vehicleCatalog),
        [dayKey, transactions, employees, vehicleCatalog],
    );

    const attendance = useMemo(
        () => buildAttendanceSummary(dayKey, transactions, employees),
        [dayKey, transactions, employees],
    );

    const compact = shareMode;

    return (
        <div className={`grid gap-3 sm:grid-cols-2 ${compact ? 'mb-3 landscape:max-md:mb-2' : 'mb-4'}`}>
            <article className="overflow-hidden rounded-2xl border border-amber-200/80 bg-white shadow-sm dark:border-amber-500/25 dark:bg-slate-900">
                <div className="border-b border-amber-100 bg-gradient-to-r from-amber-600 to-orange-600 px-4 py-3 dark:border-amber-500/20">
                    <div className="flex items-center gap-2.5">
                        <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-white/15 text-white ring-1 ring-white/20">
                            <Tractor size={17} />
                        </span>
                        <div className="min-w-0">
                            <h4 className="truncate text-sm font-bold text-white">{t('macroUsageTitle')}</h4>
                            <p className="truncate text-[11px] font-medium text-amber-100/90">
                                {macroSummary.vehicleCount > 0
                                    ? t('macroVehicleCount', { n: macroSummary.vehicleCount })
                                    : t('macroUsageEmpty')}
                            </p>
                        </div>
                    </div>
                </div>

                <div className={`space-y-3 ${compact ? 'p-3 landscape:max-md:p-2.5' : 'p-4'}`}>
                    {macroSummary.rows.length === 0 ? (
                        <p className="text-center text-sm text-slate-500 dark:text-slate-400">{t('macroUsageEmpty')}</p>
                    ) : (
                        <>
                            <div className="flex flex-wrap items-end justify-between gap-2">
                                <div>
                                    <p className="text-[10px] font-bold uppercase tracking-[0.12em] text-slate-400 dark:text-slate-500">
                                        {t('vehicleUnit')}
                                    </p>
                                    <p className="text-3xl font-black tabular-nums text-amber-700 dark:text-amber-300">
                                        {formatDashboardMetric(macroSummary.vehicleCount)}
                                    </p>
                                </div>
                                <div className="text-right">
                                    <p className="text-[10px] font-bold uppercase tracking-[0.12em] text-slate-400 dark:text-slate-500">
                                        {t('macroFuelTotal')}
                                    </p>
                                    <p className="text-lg font-black tabular-nums text-slate-800 dark:text-slate-100">
                                        {formatDashboardMetric(Math.round(macroSummary.totalLiters * 10) / 10)}{' '}
                                        <span className="text-sm font-bold text-slate-500 dark:text-slate-400">{t('litersUnit')}</span>
                                    </p>
                                </div>
                            </div>

                            <ul className="max-h-40 space-y-2 overflow-y-auto">
                                {macroSummary.rows.map((row) => (
                                    <li
                                        key={row.vehicleId}
                                        className="rounded-xl border border-slate-200/80 bg-slate-50/80 px-3 py-2 dark:border-slate-700/60 dark:bg-slate-800/50"
                                    >
                                        <div className="flex items-start justify-between gap-2">
                                            <div className="min-w-0">
                                                <p className="truncate text-xs font-bold text-slate-800 dark:text-slate-100">
                                                    {row.vehicleId}
                                                </p>
                                                <p className="truncate text-[11px] text-slate-500 dark:text-slate-400">
                                                    {row.driverLabel} · {row.workType === 'HalfDay' ? t('halfDay') : t('fullDay')}
                                                </p>
                                                {row.workDetails ? (
                                                    <p className="mt-0.5 truncate text-[10px] text-slate-400 dark:text-slate-500">
                                                        {row.workDetails}
                                                    </p>
                                                ) : null}
                                            </div>
                                            {row.liters > 0 ? (
                                                <span className="shrink-0 rounded-lg bg-amber-100 px-2 py-0.5 text-[10px] font-bold tabular-nums text-amber-900 dark:bg-amber-500/15 dark:text-amber-200">
                                                    {formatDashboardMetric(Math.round(row.liters * 10) / 10)} {t('litersUnit')}
                                                </span>
                                            ) : null}
                                        </div>
                                    </li>
                                ))}
                            </ul>
                        </>
                    )}
                </div>
            </article>

            <article className="overflow-hidden rounded-2xl border border-emerald-200/80 bg-white shadow-sm dark:border-emerald-500/25 dark:bg-slate-900">
                <div className="border-b border-emerald-100 bg-gradient-to-r from-emerald-600 to-teal-600 px-4 py-3 dark:border-emerald-500/20">
                    <div className="flex items-center gap-2.5">
                        <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-white/15 text-white ring-1 ring-white/20">
                            <Users size={17} />
                        </span>
                        <div className="min-w-0">
                            <h4 className="truncate text-sm font-bold text-white">{t('attendanceTitle')}</h4>
                            <p className="truncate text-[11px] font-medium text-emerald-100/90">
                                {t('attendanceSubtitle', { n: attendance.present })}
                            </p>
                        </div>
                    </div>
                </div>

                <div className={`space-y-3 ${compact ? 'p-3 landscape:max-md:p-2.5' : 'p-4'}`}>
                    <div>
                        <p className="text-[10px] font-bold uppercase tracking-[0.12em] text-slate-400 dark:text-slate-500">
                            {t('personUnit')}
                        </p>
                        <p className="text-3xl font-black tabular-nums text-emerald-700 dark:text-emerald-300">
                            {formatDashboardMetric(attendance.present)}
                        </p>
                    </div>

                    <div className="flex flex-wrap gap-2">
                        <span className="rounded-full bg-amber-100 px-2.5 py-1 text-[10px] font-bold text-amber-800 dark:bg-amber-500/15 dark:text-amber-200">
                            {t('attendanceLeave', { n: attendance.leave })}
                        </span>
                        <span className="rounded-full bg-rose-100 px-2.5 py-1 text-[10px] font-bold text-rose-800 dark:bg-rose-500/15 dark:text-rose-200">
                            {t('attendanceAbsent', { n: attendance.absent })}
                        </span>
                    </div>

                    {attendance.presentNames.length > 0 ? (
                        <p className="line-clamp-3 text-xs leading-relaxed text-slate-600 dark:text-slate-300">
                            {attendance.presentNames.join(' · ')}
                        </p>
                    ) : (
                        <p className="text-sm text-slate-500 dark:text-slate-400">{t('attendanceEmpty')}</p>
                    )}
                </div>
            </article>
        </div>
    );
};

export default DailyOpsCards;
