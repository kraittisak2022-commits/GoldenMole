import { useCallback, useEffect, useMemo, useState } from 'react';
import { listEmployees } from '../data/employees';
import { listWorkLogs, setWorkDayAmount } from '../data/workLogs';
import { listWorkPeriodSummaries, saveWorkPeriodSummary } from '../data/workPeriodSummaries';
import {
  buildAmountByEmployeeDate,
  calcPeriodNet,
  countWorkedDays,
  dateForDay,
  daysForHalf,
  periodKey,
  sumDayAmounts,
  type PayHalf,
} from '../lib/workSchedule';
import {
  collectMonthKeys,
  currentMonthKey,
  formatMonthLabel,
  isMonthKey,
  shiftMonth,
} from '../lib/ledgerMonth';
import type { EmployeeType, FaEmployee, FaWorkLog, FaWorkPeriodSummary } from '../types';
import { EMPLOYEE_TYPE_LABEL, formatMoney } from '../types';
import Button from './ui/Button';
import Card from './ui/Card';
import Select from './ui/Select';

const TYPE_TABS: { type: EmployeeType; label: string; totalLabel: string }[] = [
  { type: 'monthly', label: 'พนักงานรายเดือน', totalLabel: 'รวมเงินเดือน' },
  { type: 'daily', label: 'คนงานรายวัน', totalLabel: 'รวมค่าแรง' },
  { type: 'daily_driver', label: 'คนขับรถรายวัน', totalLabel: 'รวมค่ารถ' },
];

type Props = {
  onError: (message: string) => void;
};

export default function WorkSchedulePanel({ onError }: Props) {
  const [employees, setEmployees] = useState<FaEmployee[]>([]);
  const [logs, setLogs] = useState<FaWorkLog[]>([]);
  const [summaries, setSummaries] = useState<FaWorkPeriodSummary[]>([]);
  const [monthKey, setMonthKey] = useState(() => currentMonthKey());
  const [half, setHalf] = useState<PayHalf>('1-15');
  const [empType, setEmpType] = useState<EmployeeType>('daily');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);

  const monthOptions = useMemo(
    () => collectMonthKeys(logs.map((l) => l.workDate), currentMonthKey()),
    [logs],
  );

  const pKey = useMemo(() => periodKey(monthKey, half), [monthKey, half]);
  const dayNums = useMemo(() => daysForHalf(monthKey, half), [monthKey, half]);

  const typedEmployees = useMemo(
    () => employees.filter((e) => e.type === empType && !e.inactive),
    [employees, empType],
  );

  const logIndex = useMemo(() => buildAmountByEmployeeDate(logs), [logs]);
  const summaryIndex = useMemo(
    () => new Map(summaries.map((s) => [s.employeeId, s])),
    [summaries],
  );

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      const emps = await listEmployees();
      setEmployees(emps);
      const ids = emps.map((e) => e.id);
      const [w, s] = await Promise.all([
        listWorkLogs({ monthKey, employeeIds: ids }),
        listWorkPeriodSummaries(periodKey(monthKey, half)),
      ]);
      setLogs(w);
      setSummaries(s);
    } catch (err) {
      onError(err instanceof Error ? err.message : 'โหลดตารางงานไม่สำเร็จ');
    } finally {
      setLoading(false);
    }
  }, [monthKey, half, onError]);

  useEffect(() => {
    void reload();
  }, [reload]);

  const onMonthChange = (value: string) => {
    if (!isMonthKey(value)) return;
    setMonthKey(value);
  };

  const goPrev = () => onMonthChange(shiftMonth(monthKey, -1));
  const goNext = () => {
    const next = shiftMonth(monthKey, 1);
    if (next > currentMonthKey() && !monthOptions.includes(next)) return;
    onMonthChange(next);
  };

  const logsForEmployeeInPeriod = (employeeId: string) => {
    const dates = new Set(dayNums.map((d) => dateForDay(monthKey, d)));
    return logs.filter((l) => l.employeeId === employeeId && dates.has(l.workDate));
  };

  const rowStats = (emp: FaEmployee) => {
    const empLogs = logsForEmployeeInPeriod(emp.id);
    const dayTotal =
      emp.type === 'monthly'
        ? empLogs.some((l) => (Number(l.amount) || 0) > 0 || (Number(l.workDays) || 0) > 0)
          ? emp.basePay
          : 0
        : sumDayAmounts(empLogs);
    const worked =
      emp.type === 'monthly' ? countWorkedDays(empLogs) : countWorkedDays(empLogs);
    const summary = summaryIndex.get(emp.id);
    const special = summary?.specialAmount || 0;
    const advance = summary?.advanceAmount || 0;
    const net =
      emp.type === 'monthly'
        ? calcPeriodNet({
            dayTotal: emp.basePay,
            specialAmount: special,
            advanceAmount: advance,
          })
        : calcPeriodNet({ dayTotal, specialAmount: special, advanceAmount: advance });
    return { dayTotal: emp.type === 'monthly' ? emp.basePay : dayTotal, worked, special, advance, net, summary };
  };

  const sectionTotals = useMemo(() => {
    let dayTotal = 0;
    let special = 0;
    let advance = 0;
    let net = 0;
    for (const emp of typedEmployees) {
      const s = rowStats(emp);
      dayTotal += s.dayTotal;
      special += s.special;
      advance += s.advance;
      net += s.net;
    }
    return { dayTotal, special, advance, net };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- rowStats depends on logs/summaries
  }, [typedEmployees, logs, summaries, monthKey, half, empType]);

  const toggleOrSetDay = async (emp: FaEmployee, day: number) => {
    const workDate = dateForDay(monthKey, day);
    const existing = logIndex.get(emp.id)?.get(workDate);
    const defaultAmount = emp.type === 'monthly' ? 1 : emp.basePay;
    setBusy(true);
    try {
      if (existing && (Number(existing.amount) || 0) > 0) {
        await setWorkDayAmount({
          employeeId: emp.id,
          workDate,
          amount: 0,
          existingId: existing.id,
        });
      } else {
        await setWorkDayAmount({
          employeeId: emp.id,
          workDate,
          amount: defaultAmount,
          existingId: existing?.id,
        });
      }
      await reload();
    } catch (err) {
      onError(err instanceof Error ? err.message : 'บันทึกวันไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  };

  const editDayAmount = async (emp: FaEmployee, day: number, raw: string) => {
    const workDate = dateForDay(monthKey, day);
    const existing = logIndex.get(emp.id)?.get(workDate);
    const amount = Number(String(raw).replace(/,/g, '')) || 0;
    setBusy(true);
    try {
      await setWorkDayAmount({
        employeeId: emp.id,
        workDate,
        amount,
        existingId: existing?.id,
      });
      await reload();
    } catch (err) {
      onError(err instanceof Error ? err.message : 'บันทึกยอดวันไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  };

  const patchSummary = async (
    emp: FaEmployee,
    patch: Partial<Pick<FaWorkPeriodSummary, 'paid' | 'specialAmount' | 'advanceAmount' | 'notes'>>,
  ) => {
    const current = summaryIndex.get(emp.id);
    setBusy(true);
    try {
      await saveWorkPeriodSummary({
        id: current?.id,
        periodKey: pKey,
        employeeId: emp.id,
        paid: patch.paid ?? current?.paid ?? false,
        specialAmount: patch.specialAmount ?? current?.specialAmount ?? 0,
        advanceAmount: patch.advanceAmount ?? current?.advanceAmount ?? 0,
        notes: patch.notes ?? current?.notes ?? '',
      });
      await reload();
    } catch (err) {
      onError(err instanceof Error ? err.message : 'บันทึกสรุปไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  };

  const activeTab = TYPE_TABS.find((t) => t.type === empType) || TYPE_TABS[1];

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2" role="tablist" aria-label="ประเภทพนักงาน">
        {TYPE_TABS.map((t) => (
          <Button
            key={t.type}
            type="button"
            role="tab"
            aria-selected={empType === t.type}
            variant={empType === t.type ? 'primary' : 'ghost'}
            onClick={() => setEmpType(t.type)}
          >
            {t.label}
          </Button>
        ))}
      </div>

      <Card className="space-y-3 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <Button type="button" variant="secondary" className="min-h-11 min-w-11 px-0" onClick={goPrev} aria-label="เดือนก่อน">
            ‹
          </Button>
          <Select
            value={monthOptions.includes(monthKey) ? monthKey : monthOptions[0] || monthKey}
            onChange={(e) => onMonthChange(e.target.value)}
            aria-label="เดือน"
          >
            {!monthOptions.includes(monthKey) ? (
              <option value={monthKey}>{formatMonthLabel(monthKey)}</option>
            ) : null}
            {monthOptions.map((m) => (
              <option key={m} value={m}>
                {formatMonthLabel(m)}
              </option>
            ))}
          </Select>
          <Button
            type="button"
            variant="secondary"
            className="min-h-11 min-w-11 px-0"
            onClick={goNext}
            aria-label="เดือนถัดไป"
            disabled={shiftMonth(monthKey, 1) > currentMonthKey() && !monthOptions.includes(shiftMonth(monthKey, 1))}
          >
            ›
          </Button>
          <div className="flex gap-2">
            <Button
              type="button"
              variant={half === '1-15' ? 'primary' : 'secondary'}
              onClick={() => setHalf('1-15')}
            >
              วันที่ 1–15
            </Button>
            <Button
              type="button"
              variant={half === '16-end' ? 'primary' : 'secondary'}
              onClick={() => setHalf('16-end')}
            >
              วันที่ 16–สิ้นเดือน
            </Button>
          </div>
          <span className="text-sm text-muted">
            {formatMonthLabel(monthKey)} · {EMPLOYEE_TYPE_LABEL[empType]}
          </span>
        </div>
        <p className="text-xs text-muted">
          คลิกช่องวันเพื่อใส่/ลบค่าแรงตามเรทพนักงาน · ดับเบิลคลิกหรือแก้ตัวเลขในช่องเพื่อปรับยอดรายวัน
        </p>
      </Card>

      {loading ? (
        <p className="text-sm text-muted">กำลังโหลดตาราง…</p>
      ) : typedEmployees.length === 0 ? (
        <Card className="p-4">
          <p className="text-sm text-muted">
            ยังไม่มี{activeTab.label} — เพิ่มที่เมนูข้อมูลหลัก
          </p>
        </Card>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-border bg-white">
          <table className="min-w-full border-collapse text-left text-xs">
            <thead>
              <tr className="bg-slate-100 text-ink">
                <th className="sticky left-0 z-10 bg-slate-100 px-2 py-2 font-medium">รายชื่อ</th>
                <th className="px-2 py-2 font-medium">จ่ายแล้ว</th>
                {dayNums.map((d) => (
                  <th key={d} className="min-w-12 px-1 py-2 text-center font-medium tabular-nums">
                    {d}
                  </th>
                ))}
                <th className="bg-amber-100 px-2 py-2 text-right font-medium">วัน</th>
                <th className="px-2 py-2 text-right font-medium">รวม</th>
                <th className="px-2 py-2 text-right font-medium">พิเศษ</th>
                <th className="px-2 py-2 text-right font-medium">เบิก</th>
                <th className="px-2 py-2 text-right font-medium">สรุปยอด</th>
                <th className="px-2 py-2 font-medium">หมายเหตุ</th>
              </tr>
            </thead>
            <tbody>
              {typedEmployees.map((emp, idx) => {
                const stats = rowStats(emp);
                const byDate = logIndex.get(emp.id);
                return (
                  <tr
                    key={emp.id}
                    className={idx % 2 === 0 ? 'bg-white' : 'bg-slate-50/80'}
                  >
                    <td className="sticky left-0 z-10 bg-inherit px-2 py-1.5 font-medium text-ink whitespace-nowrap">
                      {emp.name}
                    </td>
                    <td className="px-2 py-1.5 text-center">
                      <input
                        type="checkbox"
                        disabled={busy}
                        checked={!!stats.summary?.paid}
                        onChange={(e) => void patchSummary(emp, { paid: e.target.checked })}
                        aria-label={`จ่ายแล้ว ${emp.name}`}
                      />
                    </td>
                    {dayNums.map((d) => {
                      const workDate = dateForDay(monthKey, d);
                      const cell = byDate?.get(workDate);
                      const amount = Number(cell?.amount) || 0;
                      return (
                        <td key={d} className="px-0.5 py-1 text-center">
                          <input
                            type="text"
                            inputMode="decimal"
                            disabled={busy}
                            className={`w-12 rounded border px-0.5 py-1 text-center tabular-nums ${
                              amount > 0
                                ? 'border-sky-300 bg-sky-50 text-ink'
                                : 'border-transparent bg-transparent text-muted'
                            }`}
                            defaultValue={amount > 0 ? String(amount) : ''}
                            key={`${emp.id}-${workDate}-${amount}`}
                            onClick={(e) => {
                              if (amount <= 0) {
                                e.preventDefault();
                                void toggleOrSetDay(emp, d);
                              }
                            }}
                            onBlur={(e) => {
                              const next = Number(String(e.target.value).replace(/,/g, '')) || 0;
                              if (next === amount) return;
                              void editDayAmount(emp, d, e.target.value);
                            }}
                            aria-label={`${emp.name} วันที่ ${d}`}
                          />
                        </td>
                      );
                    })}
                    <td className="bg-amber-50 px-2 py-1.5 text-right tabular-nums font-medium">
                      {stats.worked || ''}
                    </td>
                    <td className="px-2 py-1.5 text-right tabular-nums">
                      {formatMoney(stats.dayTotal)}
                    </td>
                    <td className="px-1 py-1">
                      <input
                        type="text"
                        inputMode="decimal"
                        disabled={busy}
                        className="w-16 rounded border border-border bg-white px-1 py-1 text-right tabular-nums"
                        defaultValue={stats.special || ''}
                        key={`sp-${emp.id}-${stats.special}`}
                        onBlur={(e) => {
                          const next = Number(String(e.target.value).replace(/,/g, '')) || 0;
                          if (next === stats.special) return;
                          void patchSummary(emp, { specialAmount: next });
                        }}
                        aria-label={`พิเศษ ${emp.name}`}
                      />
                    </td>
                    <td className="px-1 py-1">
                      <input
                        type="text"
                        inputMode="decimal"
                        disabled={busy}
                        className="w-16 rounded border border-border bg-white px-1 py-1 text-right tabular-nums"
                        defaultValue={stats.advance || ''}
                        key={`ad-${emp.id}-${stats.advance}`}
                        onBlur={(e) => {
                          const next = Number(String(e.target.value).replace(/,/g, '')) || 0;
                          if (next === stats.advance) return;
                          void patchSummary(emp, { advanceAmount: next });
                        }}
                        aria-label={`เบิก ${emp.name}`}
                      />
                    </td>
                    <td className="px-2 py-1.5 text-right tabular-nums font-semibold text-ink">
                      {formatMoney(stats.net)}
                    </td>
                    <td className="px-1 py-1">
                      <input
                        type="text"
                        disabled={busy}
                        className="min-w-24 w-full rounded border border-border bg-white px-1 py-1"
                        defaultValue={stats.summary?.notes || ''}
                        key={`note-${emp.id}-${stats.summary?.notes || ''}`}
                        onBlur={(e) => {
                          const next = e.target.value;
                          if (next === (stats.summary?.notes || '')) return;
                          void patchSummary(emp, { notes: next });
                        }}
                        aria-label={`หมายเหตุ ${emp.name}`}
                      />
                    </td>
                  </tr>
                );
              })}
              <tr className="bg-orange-100 font-semibold text-ink">
                <td className="sticky left-0 z-10 bg-orange-100 px-2 py-2" colSpan={2}>
                  {activeTab.totalLabel}
                </td>
                <td colSpan={dayNums.length} />
                <td className="bg-orange-100 px-2 py-2" />
                <td className="px-2 py-2 text-right tabular-nums">{formatMoney(sectionTotals.dayTotal)}</td>
                <td className="px-2 py-2 text-right tabular-nums">{formatMoney(sectionTotals.special)}</td>
                <td className="px-2 py-2 text-right tabular-nums">{formatMoney(sectionTotals.advance)}</td>
                <td className="px-2 py-2 text-right tabular-nums">{formatMoney(sectionTotals.net)}</td>
                <td />
              </tr>
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
