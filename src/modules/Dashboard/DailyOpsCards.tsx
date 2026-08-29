import { useMemo } from 'react';
import { Fuel, UserRound, Users } from 'lucide-react';
import type { Employee, Transaction } from '../../types';
import type { VehicleCatalogRow } from '../../utils/vehicleCatalog';
import type { AttendancePositionGroup } from '../../utils/advanceEmployeeFilter';
import { useShareLocale } from '../Share/shareI18n';
import { formatDashboardMetric, VEHICLE_BUTTON_COLORS } from './countRecordUtils';
import {
    buildAttendanceSummary,
    buildMacroUsageSummary,
    type AttendancePerson,
} from './dailyOpsCardUtils';
import ExcavatorIcon from './ExcavatorIcon';

interface DailyOpsCardsProps {
    dayKey: string;
    transactions: Transaction[];
    employees: Employee[];
    shareMode?: boolean;
    vehicleCatalog?: VehicleCatalogRow[];
}

const GROUP_ORDER: AttendancePositionGroup[] = ['sandYard', 'driver', 'other'];

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

    const presentByGroup = useMemo(() => {
        const map: Record<AttendancePositionGroup, AttendancePerson[]> = {
            sandYard: [],
            driver: [],
            other: [],
        };
        for (const person of attendance.presentPeople) {
            map[person.group].push(person);
        }
        return map;
    }, [attendance.presentPeople]);

    const compact = shareMode;
    const groupLabel = (g: AttendancePositionGroup) => {
        if (g === 'sandYard') return t('attendanceGroupSand');
        if (g === 'driver') return t('attendanceGroupDriver');
        return t('attendanceGroupOther');
    };

    return (
        <div className={`grid gap-3 sm:grid-cols-2 ${compact ? 'mb-3 landscape:max-md:mb-2' : 'mb-4'}`}>
            <article className="overflow-hidden rounded-2xl border border-amber-200/80 bg-white shadow-sm dark:border-amber-500/25 dark:bg-slate-900">
                <div className="border-b border-amber-100 bg-gradient-to-r from-amber-600 to-orange-600 px-4 py-3 dark:border-amber-500/20">
                    <div className="flex items-center gap-2.5">
                        <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-white/15 text-white ring-1 ring-white/20">
                            <ExcavatorIcon size={18} />
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

                            <div className="grid max-h-64 grid-cols-3 gap-1.5 overflow-y-auto sm:grid-cols-3">
                                {macroSummary.rows.map((row, index) => {
                                    const accent = VEHICLE_BUTTON_COLORS[index % VEHICLE_BUTTON_COLORS.length];
                                    return (
                                        <article
                                            key={row.vehicleId}
                                            className="relative overflow-hidden rounded-lg border border-white/10 bg-slate-900 text-white shadow-sm shadow-slate-900/10"
                                        >
                                            <div
                                                className="absolute inset-0 opacity-90"
                                                style={{
                                                    background: `linear-gradient(145deg, ${accent} 0%, ${accent}cc 42%, #0f172a 100%)`,
                                                }}
                                            />
                                            <div className="relative flex flex-col gap-1 p-1.5">
                                                <div className="flex flex-col items-center gap-1">
                                                    <div className="flex w-full items-center justify-center rounded-md bg-white/10 py-1 ring-1 ring-white/15">
                                                        <ExcavatorIcon size={22} className="text-white" />
                                                    </div>
                                                    <p className="w-full truncate text-center text-[10px] font-bold leading-tight">
                                                        {row.vehicleId}
                                                    </p>
                                                </div>
                                                <p className="flex items-center gap-0.5 truncate text-[9px] font-medium text-white/80">
                                                    <UserRound size={9} className="shrink-0" />
                                                    {row.driverLabel}
                                                </p>
                                                <div className="flex flex-wrap gap-0.5">
                                                    <span className="rounded bg-black/25 px-1 py-0.5 text-[8px] font-bold text-white/90">
                                                        {row.workType === 'HalfDay' ? t('halfDay') : t('fullDay')}
                                                    </span>
                                                    {row.liters > 0 ? (
                                                        <span className="inline-flex items-center gap-0.5 rounded bg-amber-300/90 px-1 py-0.5 text-[8px] font-bold text-amber-950">
                                                            <Fuel size={8} />
                                                            {formatDashboardMetric(Math.round(row.liters * 10) / 10)}
                                                        </span>
                                                    ) : null}
                                                </div>
                                            </div>
                                        </article>
                                    );
                                })}
                            </div>
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

                    {attendance.presentPeople.length > 0 ? (
                        <div className="max-h-64 space-y-3 overflow-y-auto">
                            {GROUP_ORDER.map((group) => {
                                const people = presentByGroup[group];
                                if (people.length === 0) return null;
                                return (
                                    <div key={group}>
                                        <p className="mb-1.5 text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500 dark:text-slate-400">
                                            {groupLabel(group)} · {people.length}
                                        </p>
                                        <div className="grid grid-cols-2 gap-2">
                                            {people.map((person) => (
                                                <article
                                                    key={person.id}
                                                    className="flex items-center gap-2 rounded-xl border border-emerald-100 bg-emerald-50/70 px-2.5 py-2 dark:border-emerald-500/20 dark:bg-emerald-500/10"
                                                >
                                                    <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-emerald-100 text-sm font-bold text-emerald-700 dark:bg-emerald-500/20 dark:text-emerald-200">
                                                        {(person.name || '?').charAt(0)}
                                                    </div>
                                                    <div className="min-w-0 flex-1">
                                                        <p className="truncate text-xs font-bold text-slate-800 dark:text-slate-100">
                                                            {person.name}
                                                        </p>
                                                        {person.ot ? (
                                                            <span className="mt-0.5 inline-block rounded bg-violet-100 px-1.5 py-0.5 text-[9px] font-bold text-violet-800 dark:bg-violet-500/20 dark:text-violet-200">
                                                                OT
                                                            </span>
                                                        ) : null}
                                                    </div>
                                                </article>
                                            ))}
                                        </div>
                                    </div>
                                );
                            })}
                        </div>
                    ) : (
                        <p className="text-sm text-slate-500 dark:text-slate-400">{t('attendanceEmpty')}</p>
                    )}
                </div>
            </article>
        </div>
    );
};

export default DailyOpsCards;
