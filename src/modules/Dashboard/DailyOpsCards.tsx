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
            <article className="overflow-hidden rounded-2xl border border-amber-200/70 bg-white shadow-sm dark:border-amber-500/20 dark:bg-slate-900">
                <div className="flex items-center justify-between gap-3 border-b border-amber-100/80 bg-gradient-to-r from-amber-500 to-orange-500 px-3.5 py-2.5 dark:border-amber-500/15">
                    <div className="flex min-w-0 items-center gap-2.5">
                        <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-white/20 text-white ring-1 ring-white/25">
                            <ExcavatorIcon size={16} />
                        </span>
                        <div className="min-w-0">
                            <h4 className="truncate text-sm font-bold text-white">{t('macroUsageTitle')}</h4>
                            <p className="truncate text-[11px] font-medium text-amber-50/90">
                                {macroSummary.vehicleCount > 0
                                    ? t('macroVehicleCount', { n: macroSummary.vehicleCount })
                                    : t('macroUsageEmpty')}
                            </p>
                        </div>
                    </div>
                    {macroSummary.rows.length > 0 ? (
                        <div className="shrink-0 rounded-lg bg-white/15 px-2.5 py-1 text-right ring-1 ring-white/20">
                            <p className="text-[9px] font-bold uppercase tracking-wide text-amber-50/80">
                                {t('macroFuelTotal')}
                            </p>
                            <p className="text-sm font-black tabular-nums text-white">
                                {formatDashboardMetric(Math.round(macroSummary.totalLiters * 10) / 10)}
                                <span className="ml-0.5 text-[10px] font-bold text-amber-50/90">{t('litersUnit')}</span>
                            </p>
                        </div>
                    ) : null}
                </div>

                <div className={compact ? 'p-2.5 landscape:max-md:p-2' : 'p-3'}>
                    {macroSummary.rows.length === 0 ? (
                        <p className="py-4 text-center text-sm text-slate-500 dark:text-slate-400">{t('macroUsageEmpty')}</p>
                    ) : (
                        <ul className="max-h-72 space-y-1.5 overflow-y-auto">
                            {macroSummary.rows.map((row, index) => {
                                const accent = VEHICLE_BUTTON_COLORS[index % VEHICLE_BUTTON_COLORS.length];
                                return (
                                    <li
                                        key={row.vehicleId}
                                        className="flex items-center gap-2.5 rounded-xl border border-slate-100 bg-slate-50/80 px-2 py-1.5 dark:border-white/10 dark:bg-slate-800/60"
                                    >
                                        <span
                                            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-white shadow-sm"
                                            style={{ backgroundColor: accent }}
                                        >
                                            <ExcavatorIcon size={16} />
                                        </span>
                                        <div className="min-w-0 flex-1">
                                            <p className="truncate text-xs font-bold leading-snug text-slate-800 dark:text-slate-100">
                                                {row.vehicleId}
                                            </p>
                                            <div className="mt-0.5 flex min-w-0 flex-wrap items-center gap-1.5">
                                                <span className="inline-flex max-w-full items-center gap-0.5 truncate text-[10px] font-medium text-slate-500 dark:text-slate-400">
                                                    <UserRound size={10} className="shrink-0" />
                                                    <span className="truncate">{row.driverLabel}</span>
                                                </span>
                                                <span className="rounded-md bg-slate-200/80 px-1.5 py-px text-[9px] font-bold text-slate-600 dark:bg-slate-700 dark:text-slate-300">
                                                    {row.workType === 'HalfDay' ? t('halfDay') : t('fullDay')}
                                                </span>
                                            </div>
                                        </div>
                                        {row.liters > 0 ? (
                                            <span className="inline-flex shrink-0 items-center gap-1 rounded-lg bg-amber-100 px-2 py-1 text-[11px] font-bold tabular-nums text-amber-900 dark:bg-amber-500/20 dark:text-amber-200">
                                                <Fuel size={11} className="shrink-0 opacity-80" />
                                                {formatDashboardMetric(Math.round(row.liters * 10) / 10)}
                                            </span>
                                        ) : (
                                            <span className="shrink-0 rounded-lg bg-slate-100 px-2 py-1 text-[10px] font-semibold text-slate-400 dark:bg-slate-700/80 dark:text-slate-500">
                                                —
                                            </span>
                                        )}
                                    </li>
                                );
                            })}
                        </ul>
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
