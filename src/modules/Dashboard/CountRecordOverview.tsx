import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { Truck, Droplets, AlertTriangle, Timer } from 'lucide-react';
import type { Employee, Transaction } from '../../types';
import {
    VEHICLE_BUTTON_COLORS,
    buildCountRecordSandUnit,
    buildCountRecordTripUnits,
    countRecordMenuStatusLabel,
    formatDashboardMetric,
} from './countRecordUtils';

interface CountRecordOverviewProps {
    dayKey: string;
    transactions: Transaction[];
    employees?: Employee[];
    compact?: boolean;
    showHeader?: boolean;
    pulseToken?: number;
}

const SAND_RECENT_LAPS = 4;

function TripVehicleCard({
    unit,
    index,
    compact,
    bump,
}: {
    unit: ReturnType<typeof buildCountRecordTripUnits>[number];
    index: number;
    compact?: boolean;
    bump?: boolean;
}) {
    const bg = VEHICLE_BUTTON_COLORS[index % VEHICLE_BUTTON_COLORS.length];
    const lastLap = unit.lapTimes[unit.lapTimes.length - 1];

    return (
        <div
            className={`rounded-2xl text-white shadow-md overflow-hidden transition-transform duration-300 ${compact ? 'min-h-[100px]' : 'min-h-[120px]'} ${bump ? 'scale-[1.03] animate-bounce-short' : ''}`}
            style={{ backgroundColor: bg, opacity: unit.broken ? 0.55 : 1 }}
        >
            <div className={`${compact ? 'p-2.5' : 'p-3'} flex flex-col h-full`}>
                <div className="flex items-start justify-between gap-2">
                    <span className="text-[10px] font-bold bg-white/20 rounded-full px-2 py-0.5">
                        คันที่ {index + 1}
                    </span>
                    {unit.broken && (
                        <span className="inline-flex items-center gap-0.5 text-[10px] font-bold bg-amber-400/90 text-amber-950 rounded-full px-1.5 py-0.5">
                            <AlertTriangle size={10} />
                            รถเสีย
                        </span>
                    )}
                </div>
                <div className="flex-1 flex flex-col items-center justify-center py-1">
                    <div className={`font-black tabular-nums leading-none ${compact ? 'text-3xl' : 'text-4xl'}`}>
                        {unit.rounds}
                    </div>
                    <div className="text-[11px] font-semibold opacity-90 mt-0.5">เที่ยว</div>
                    {(unit.morning > 0 || unit.afternoon > 0) && (
                        <div className="text-[10px] font-medium opacity-80 mt-1">
                            เช้า {formatDashboardMetric(unit.morning)} · บ่าย {formatDashboardMetric(unit.afternoon)}
                        </div>
                    )}
                </div>
                <div className="text-center">
                    <div className={`font-extrabold leading-tight ${compact ? 'text-xs' : 'text-sm'}`}>{unit.vehicleId}</div>
                    <div className="text-[11px] font-medium opacity-90 truncate">คนขับ: {unit.driverLabel}</div>
                    {lastLap && (
                        <div className="text-[10px] opacity-75 mt-0.5 truncate">ล่าสุด {lastLap}</div>
                    )}
                </div>
            </div>
        </div>
    );
}

function SandLapChip({ roundNo, stamp }: { roundNo: number; stamp: string }) {
    return (
        <span className="inline-flex items-center gap-1 rounded-full border border-pink-300 bg-white px-2 py-1 text-[11px] font-semibold text-pink-900">
            <span className="text-pink-600">รอบ {roundNo}</span>
            <span className="text-slate-600">{stamp}</span>
        </span>
    );
}

function CountRecordPanelShell({
    title,
    icon,
    iconColor,
    backgroundColor,
    borderColor,
    children,
}: {
    title: string;
    icon: ReactNode;
    iconColor: string;
    backgroundColor: string;
    borderColor: string;
    children: ReactNode;
}) {
    return (
        <div
            className="rounded-[22px] border-2 overflow-hidden shadow-sm flex flex-col min-h-[220px]"
            style={{ backgroundColor, borderColor }}
        >
            <div className="px-3.5 py-3 flex items-center gap-2 text-white shrink-0" style={{ backgroundColor: iconColor }}>
                {icon}
                <span className="font-extrabold text-sm truncate">{title}</span>
            </div>
            <div className="flex-1 p-2 min-h-0">{children}</div>
        </div>
    );
}

const CountRecordOverview = ({
    dayKey,
    transactions,
    employees = [],
    compact = false,
    showHeader = true,
    pulseToken = 0,
}: CountRecordOverviewProps) => {
    const [bump, setBump] = useState(false);

    useEffect(() => {
        if (pulseToken <= 0) return;
        setBump(true);
        const timer = window.setTimeout(() => setBump(false), 520);
        return () => window.clearTimeout(timer);
    }, [pulseToken]);

    const tripUnits = useMemo(
        () => buildCountRecordTripUnits(dayKey, transactions, employees),
        [dayKey, transactions, employees],
    );
    const sandUnit = useMemo(
        () => buildCountRecordSandUnit(dayKey, transactions),
        [dayKey, transactions],
    );
    const statusLabel = useMemo(
        () => countRecordMenuStatusLabel(dayKey, transactions),
        [dayKey, transactions],
    );

    const sandRecentStart = sandUnit
        ? Math.max(0, sandUnit.lapTimes.length - SAND_RECENT_LAPS)
        : 0;

    const tripWithLaps = tripUnits.filter((u) => u.lapTimes.length > 0);

    return (
        <div className={compact ? 'space-y-3' : 'space-y-4'}>
            {showHeader && (
                <div className="flex flex-wrap items-center gap-2">
                    <div className="flex items-center gap-2 text-slate-800">
                        <span className="w-8 h-8 rounded-xl bg-[#1565C0] flex items-center justify-center text-white">
                            <Timer size={16} />
                        </span>
                        <div>
                            <h3 className="font-extrabold text-base">บันทึกและนับจำนวน</h3>
                            {statusLabel && (
                                <p className="text-xs font-semibold text-slate-500">{statusLabel}</p>
                            )}
                        </div>
                    </div>
                </div>
            )}

            <div className={`grid gap-3 ${compact ? 'grid-cols-1' : 'grid-cols-1 lg:grid-cols-2'}`}>
                <CountRecordPanelShell
                    title="จำนวนเที่ยวรถ"
                    icon={<Truck size={18} />}
                    iconColor="#1565C0"
                    backgroundColor="#E3F2FD"
                    borderColor={bump ? '#1565C0' : '#90CAF9'}
                >
                    {tripUnits.length === 0 ? (
                        <div className="h-full min-h-[140px] flex flex-col items-center justify-center text-center px-4">
                            <p className="text-sm font-semibold text-slate-500">ยังไม่มีเที่ยวที่บันทึก</p>
                            <p className="text-xs text-slate-400 mt-1">ข้อมูลจากแอปจะแสดงที่นี่แบบเรียลไทม์</p>
                        </div>
                    ) : (
                        <div className="space-y-2">
                            <div
                                className={
                                    tripUnits.length <= 2
                                        ? `grid gap-2 ${tripUnits.length === 1 ? 'grid-cols-1' : 'grid-cols-2'}`
                                        : 'grid grid-cols-2 gap-2'
                                }
                            >
                                {tripUnits.map((unit, i) => (
                                    <TripVehicleCard
                                        key={unit.id}
                                        unit={unit}
                                        index={i}
                                        compact={compact || tripUnits.length > 2}
                                        bump={bump}
                                    />
                                ))}
                            </div>
                            <div className="rounded-xl border border-[#DCE6F2] bg-[#F4F7FA] px-3 py-2.5">
                                <div className="text-[13px] font-extrabold text-[#455A64]">บันทึกล่าสุด</div>
                                {tripWithLaps.length > 0 ? (
                                    <div className="mt-1.5 space-y-1">
                                        {tripWithLaps.map((u) => (
                                            <p key={u.id} className="text-[11.5px] font-semibold text-[#52647B] truncate">
                                                {u.vehicleId}: {u.lapTimes[u.lapTimes.length - 1]} ({u.rounds} เที่ยว)
                                            </p>
                                        ))}
                                    </div>
                                ) : (
                                    <p className="mt-1 text-[11.5px] font-semibold text-slate-500">ยังไม่มีเที่ยวที่บันทึก</p>
                                )}
                            </div>
                        </div>
                    )}
                </CountRecordPanelShell>

                <CountRecordPanelShell
                    title="การร่อนทราย"
                    icon={<Droplets size={18} />}
                    iconColor="#AD1457"
                    backgroundColor="#FCE4EC"
                    borderColor={bump ? '#AD1457' : '#F48FB1'}
                >
                    {!sandUnit || sandUnit.rounds <= 0 ? (
                        <div className="h-full min-h-[140px] flex flex-col items-center justify-center text-center px-4">
                            <p className="text-sm font-semibold text-slate-500">ยังไม่มีรอบที่บันทึก</p>
                            <p className="text-xs text-slate-400 mt-1">กดบันทึกในแอปเพื่อนับรอบร่อนทราย</p>
                        </div>
                    ) : (
                        <div className="flex flex-col h-full min-h-[140px]">
                            <div
                                className={`flex-1 flex flex-col items-center justify-center rounded-2xl bg-gradient-to-br from-pink-600 to-pink-700 text-white shadow-inner mx-1 my-1 px-4 py-5 transition-transform duration-300 ${bump ? 'scale-[1.02] animate-bounce-short' : ''}`}
                            >
                                <div className="text-5xl font-black tabular-nums leading-none">{sandUnit.rounds}</div>
                                <div className="text-sm font-bold mt-1 opacity-95">รอบ</div>
                                {(sandUnit.morning > 0 || sandUnit.afternoon > 0) && (
                                    <div className="text-xs font-semibold mt-2 opacity-90">
                                        เช้า {sandUnit.morning} · บ่าย {sandUnit.afternoon}
                                    </div>
                                )}
                                {sandUnit.lapTimes.length > 0 && (
                                    <div className="text-[11px] mt-2 opacity-80">
                                        ล่าสุด {sandUnit.lapTimes[sandUnit.lapTimes.length - 1]}
                                    </div>
                                )}
                            </div>
                            {sandUnit.lapTimes.length > 0 && (
                                <div className="px-1 pt-2 pb-1">
                                    <div className="flex flex-wrap gap-1.5">
                                        {sandUnit.lapTimes.slice(sandRecentStart).map((stamp, i) => (
                                            <SandLapChip
                                                key={`${stamp}-${sandRecentStart + i}`}
                                                roundNo={sandRecentStart + i + 1}
                                                stamp={stamp}
                                            />
                                        ))}
                                    </div>
                                </div>
                            )}
                        </div>
                    )}
                </CountRecordPanelShell>
            </div>
        </div>
    );
};

export default CountRecordOverview;
