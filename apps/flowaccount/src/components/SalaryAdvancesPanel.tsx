import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { listEmployees } from '../data/employees';
import {
  deleteSalaryAdvance,
  listSalaryAdvances,
  saveSalaryAdvance,
} from '../data/salaryAdvances';
import {
  collectMonthKeys,
  currentMonthKey,
  formatMonthLabel,
  isMonthKey,
  shiftMonth,
} from '../lib/ledgerMonth';
import type { FaEmployee, FaSalaryAdvance } from '../types';
import { EMPLOYEE_TYPE_LABEL, formatMoney } from '../types';
import Button from './ui/Button';
import Card from './ui/Card';
import DataTable, { Column } from './ui/DataTable';
import Field from './ui/Field';
import Input from './ui/Input';
import Modal from './ui/Modal';
import MoneyInput from './ui/MoneyInput';
import Select from './ui/Select';

const today = () => new Date().toISOString().slice(0, 10);

type Props = {
  onError: (message: string) => void;
  reloadToken?: number;
  onChanged?: () => void;
};

export default function SalaryAdvancesPanel({ onError, reloadToken = 0, onChanged }: Props) {
  const [rows, setRows] = useState<FaSalaryAdvance[]>([]);
  const [employees, setEmployees] = useState<FaEmployee[]>([]);
  const [monthKey, setMonthKey] = useState(() => currentMonthKey());
  const [loading, setLoading] = useState(true);
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);

  const [advanceDate, setAdvanceDate] = useState(today());
  const [employeeId, setEmployeeId] = useState('');
  const [amount, setAmount] = useState<number | ''>('');
  const [notes, setNotes] = useState('');

  const monthOptions = useMemo(
    () => collectMonthKeys(rows.map((r) => r.advanceDate), currentMonthKey()),
    [rows],
  );

  const monthRows = useMemo(
    () => rows.filter((r) => r.advanceDate.startsWith(monthKey)),
    [rows, monthKey],
  );

  const monthTotal = useMemo(
    () => monthRows.reduce((s, r) => s + (Number(r.amount) || 0), 0),
    [monthRows],
  );

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      const [a, e] = await Promise.all([listSalaryAdvances(), listEmployees()]);
      setRows(a);
      setEmployees(e);
      if (!employeeId && e[0]) setEmployeeId(e[0].id);
      const months = collectMonthKeys(a.map((x) => x.advanceDate), currentMonthKey());
      setMonthKey((prev) => (months.includes(prev) ? prev : months[0] || currentMonthKey()));
    } catch (err) {
      onError(err instanceof Error ? err.message : 'โหลดรายการเบิกไม่สำเร็จ');
    } finally {
      setLoading(false);
    }
  }, [onError, employeeId]);

  useEffect(() => {
    void reload();
  }, [reload, reloadToken]);

  const onMonthChange = (value: string) => {
    if (!isMonthKey(value)) return;
    setMonthKey(value);
  };

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const emp = employees.find((x) => x.id === employeeId);
    if (!emp || amount === '' || Number(amount) < 0) return;
    setBusy(true);
    try {
      await saveSalaryAdvance({
        advanceDate,
        employeeId: emp.id,
        employeeName: emp.name,
        amount: Number(amount),
        notes,
      });
      setOpen(false);
      setAmount('');
      setNotes('');
      await reload();
      onChanged?.();
    } catch (err) {
      onError(err instanceof Error ? err.message : 'บันทึกเบิกไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  };

  const onDelete = async (row: FaSalaryAdvance) => {
    const ok = window.confirm(`ลบรายการเบิกของ ${row.employeeName} วันที่ ${row.advanceDate}?`);
    if (!ok) return;
    try {
      await deleteSalaryAdvance(row.id);
      await reload();
      onChanged?.();
    } catch (err) {
      onError(err instanceof Error ? err.message : 'ลบรายการเบิกไม่สำเร็จ');
    }
  };

  const columns: Column<FaSalaryAdvance>[] = [
    { key: 'date', header: 'วันที่เบิก', render: (r) => r.advanceDate },
    {
      key: 'name',
      header: 'รายชื่อคนเบิก',
      render: (r) => r.employeeName,
    },
    {
      key: 'amount',
      header: 'จำนวนเงินที่เบิก',
      className: 'text-right tabular-nums font-medium',
      render: (r) => formatMoney(r.amount),
    },
    {
      key: 'notes',
      header: 'หมายเหตุ',
      render: (r) => r.notes || '—',
    },
    {
      key: 'actions',
      header: '',
      render: (r) => (
        <Button variant="ghost" className="min-h-9 px-2 text-destructive" onClick={() => void onDelete(r)}>
          ลบ
        </Button>
      ),
    },
  ];

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <Card className="flex-1 p-4">
          <div className="flex flex-wrap items-center gap-2">
            <Button
              type="button"
              variant="secondary"
              className="min-h-11 min-w-11 px-0"
              aria-label="เดือนก่อน"
              onClick={() => onMonthChange(shiftMonth(monthKey, -1))}
            >
              ‹
            </Button>
            <Select
              value={monthOptions.includes(monthKey) ? monthKey : monthOptions[0] || monthKey}
              onChange={(e) => onMonthChange(e.target.value)}
              aria-label="เดือนรายการเบิก"
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
              aria-label="เดือนถัดไป"
              disabled={
                shiftMonth(monthKey, 1) > currentMonthKey() &&
                !monthOptions.includes(shiftMonth(monthKey, 1))
              }
              onClick={() => onMonthChange(shiftMonth(monthKey, 1))}
            >
              ›
            </Button>
            <span className="text-sm text-muted">{formatMonthLabel(monthKey)}</span>
          </div>
          <p className="mt-2 text-sm text-muted">
            รวมเบิกเดือนนี้:{' '}
            <span className="font-semibold tabular-nums text-ink">{formatMoney(monthTotal)}</span> บาท ·{' '}
            {monthRows.length} รายการ
          </p>
        </Card>
        <Button onClick={() => setOpen(true)}>บันทึกเบิกเงิน</Button>
      </div>

      {loading ? (
        <p className="text-sm text-muted">กำลังโหลด…</p>
      ) : (
        <DataTable
          columns={columns}
          rows={monthRows}
          rowKey={(r) => r.id}
          emptyText="ยังไม่มีรายการเบิกในเดือนนี้"
        />
      )}

      <Modal
        open={open}
        title="บันทึกรายการเบิกเงิน"
        onClose={() => !busy && setOpen(false)}
        footer={
          <>
            <Button variant="secondary" disabled={busy} onClick={() => setOpen(false)}>
              ยกเลิก
            </Button>
            <Button type="submit" form="adv-form" disabled={busy}>
              บันทึก
            </Button>
          </>
        }
      >
        <form id="adv-form" className="space-y-4" onSubmit={submit}>
          <Field id="adv-date" label="วันที่เบิก">
            <Input
              id="adv-date"
              type="date"
              value={advanceDate}
              onChange={(e) => setAdvanceDate(e.target.value)}
              required
            />
          </Field>
          <Field id="adv-emp" label="รายชื่อคนเบิก">
            <Select
              id="adv-emp"
              value={employeeId}
              onChange={(e) => setEmployeeId(e.target.value)}
              required
            >
              {employees.length === 0 ? (
                <option value="">ยังไม่มีพนักงาน — เพิ่มในตารางการทำงานก่อน</option>
              ) : (
                employees.map((emp) => (
                  <option key={emp.id} value={emp.id}>
                    {emp.name} ({EMPLOYEE_TYPE_LABEL[emp.type]})
                  </option>
                ))
              )}
            </Select>
          </Field>
          <Field id="adv-amt" label="จำนวนเงินที่เบิก (บาท)">
            <MoneyInput id="adv-amt" value={amount} onValueChange={setAmount} required />
          </Field>
          <Field id="adv-notes" label="หมายเหตุ">
            <Input id="adv-notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
          </Field>
        </form>
      </Modal>
    </div>
  );
}
